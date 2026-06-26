import Foundation
import XCTest
@testable import wetrans

final class TransferQueueTests: XCTestCase {
    func testEnqueueRunsTaskAndRecordsProgress() async throws {
        let task = makeTask(totalBytes: 100)
        let engine = ScriptedTransferEngine(behaviors: [
            task.id: .succeed([
                TransferProgress(transferredBytes: 40, totalBytes: 100, speedBytesPerSecond: 12),
                TransferProgress(transferredBytes: 100, totalBytes: 100, speedBytesPerSecond: 24)
            ])
        ])
        let store = InMemoryTransferHistoryStore()
        let queue = TransferQueue(engine: engine, historyStore: store, now: fixedNow)

        await queue.enqueue([task])

        try await waitUntil {
            await queue.snapshot().first?.status == .succeeded
        }
        let finishedSnapshot = await queue.snapshot()
        let saved = try XCTUnwrap(finishedSnapshot.first)
        XCTAssertEqual(saved.transferredBytes, 100)
        XCTAssertEqual(saved.progress, 1)
        XCTAssertEqual(saved.speedBytesPerSecond, 24)
        XCTAssertEqual(saved.startedAt, fixedNow())
        XCTAssertEqual(saved.completedAt, fixedNow())
    }

    func testSchedulerHonorsGlobalAndPerHostLimits() async throws {
        let hostA = UUID()
        let hostB = UUID()
        let taskA1 = makeTask(hostId: hostA, fileName: "a1.txt")
        let taskA2 = makeTask(hostId: hostA, fileName: "a2.txt")
        let taskB1 = makeTask(hostId: hostB, fileName: "b1.txt")
        let taskB2 = makeTask(hostId: hostB, fileName: "b2.txt")
        let engine = ScriptedTransferEngine(behaviors: [
            taskA1.id: .block,
            taskA2.id: .block,
            taskB1.id: .block,
            taskB2.id: .block
        ])
        let queue = TransferQueue(
            engine: engine,
            historyStore: InMemoryTransferHistoryStore(),
            globalConcurrencyLimit: 2,
            perHostConcurrencyLimit: 1,
            now: fixedNow
        )

        await queue.enqueue([taskA1, taskA2, taskB1, taskB2])

        try await waitUntil {
            await engine.startedTaskIds.count == 2
        }
        let started = await Set(engine.startedTaskIds)
        XCTAssertEqual(started, [taskA1.id, taskB1.id])
        let stats = await engine.stats()
        XCTAssertEqual(stats.maxRunningTotal, 2)
        XCTAssertEqual(stats.maxRunningByHost[hostA], 1)
        XCTAssertEqual(stats.maxRunningByHost[hostB], 1)
    }

    func testCancelPendingTaskDoesNotRunEngine() async throws {
        let running = makeTask(fileName: "running.txt")
        let pending = makeTask(fileName: "pending.txt")
        let engine = ScriptedTransferEngine(behaviors: [
            running.id: .block,
            pending.id: .block
        ])
        let queue = TransferQueue(
            engine: engine,
            historyStore: InMemoryTransferHistoryStore(),
            globalConcurrencyLimit: 1,
            now: fixedNow
        )

        await queue.enqueue([running, pending])
        try await waitUntil {
            await engine.startedTaskIds == [running.id]
        }
        await queue.cancel(taskId: pending.id)

        let snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.first(where: { $0.id == pending.id })?.status, .cancelled)
        let startedAfterCancel = await engine.startedTaskIds
        XCTAssertFalse(startedAfterCancel.contains(pending.id))
    }

    func testCancelRunningTaskMarksCancelled() async throws {
        let task = makeTask()
        let engine = ScriptedTransferEngine(behaviors: [task.id: .block])
        let queue = TransferQueue(engine: engine, historyStore: InMemoryTransferHistoryStore(), now: fixedNow)

        await queue.enqueue([task])
        try await waitUntil {
            await engine.startedTaskIds == [task.id]
        }
        await queue.cancel(taskId: task.id)

        try await waitUntil {
            await queue.snapshot().first?.status == .cancelled
        }
        let cancelledSnapshot = await queue.snapshot()
        let cancelled = try XCTUnwrap(cancelledSnapshot.first)
        XCTAssertEqual(cancelled.completedAt, fixedNow())
    }

    func testRetryFailedTaskResetsStateAndRunsAgain() async throws {
        let task = makeTask(totalBytes: 20)
        let engine = ScriptedTransferEngine(behaviors: [task.id: .fail("disk full")])
        let queue = TransferQueue(engine: engine, historyStore: InMemoryTransferHistoryStore(), now: fixedNow)

        await queue.enqueue([task])
        try await waitUntil {
            await queue.snapshot().first?.status == .failed
        }
        await engine.setBehavior(.succeed([]), for: task.id)
        await queue.retry(taskId: task.id)

        try await waitUntil {
            await queue.snapshot().first?.status == .succeeded
        }
        let retriedSnapshot = await queue.snapshot()
        let retried = try XCTUnwrap(retriedSnapshot.first)
        XCTAssertNil(retried.errorMessage)
        XCTAssertEqual(retried.transferredBytes, 20)
        XCTAssertEqual(retried.progress, 1)
        let startedTaskIds = await engine.startedTaskIds
        XCTAssertEqual(startedTaskIds, [task.id, task.id])
    }

    func testStartupMarksPreviouslyRunningTasksFailed() async throws {
        let running = makeTask(status: .running, startedAt: Date(timeIntervalSince1970: 1_700_000_000))
        let succeeded = makeTask(status: .succeeded, completedAt: Date(timeIntervalSince1970: 1_700_000_100))
        let store = InMemoryTransferHistoryStore(initialTasks: [running, succeeded])

        let queue = TransferQueue(engine: ScriptedTransferEngine(), historyStore: store, now: fixedNow)

        let snapshot = await queue.snapshot()
        XCTAssertEqual(snapshot.first(where: { $0.id == running.id })?.status, .failed)
        XCTAssertEqual(
            snapshot.first(where: { $0.id == running.id })?.errorMessage,
            "Transfer interrupted because wetrans was closed."
        )
        XCTAssertEqual(snapshot.first(where: { $0.id == running.id })?.completedAt, fixedNow())
        XCTAssertEqual(snapshot.first(where: { $0.id == succeeded.id })?.status, .succeeded)
    }

    func testQueueSavesAfterStateTransitionsAndClearFinished() async throws {
        let task = makeTask()
        let store = InMemoryTransferHistoryStore()
        let queue = TransferQueue(
            engine: ScriptedTransferEngine(behaviors: [task.id: .succeed([])]),
            historyStore: store,
            now: fixedNow
        )

        await queue.enqueue([task])
        try await waitUntil {
            await queue.snapshot().first?.status == .succeeded
        }
        await queue.clearFinished(statuses: [.succeeded])

        let savedSnapshots = await store.savedSnapshots
        XCTAssertTrue(savedSnapshots.contains { $0.contains { $0.id == task.id && $0.status == .pending } })
        XCTAssertTrue(savedSnapshots.contains { $0.contains { $0.id == task.id && $0.status == .running } })
        XCTAssertTrue(savedSnapshots.contains { $0.contains { $0.id == task.id && $0.status == .succeeded } })
        XCTAssertEqual(savedSnapshots.last, [])
    }
}

private enum EngineBehavior: Sendable {
    case succeed([TransferProgress])
    case fail(String)
    case block
}

private struct ScriptedEngineError: Error, LocalizedError, Sendable {
    let message: String
    var errorDescription: String? { message }
}

private actor ScriptedTransferEngine: TransferEngine {
    private var behaviors: [UUID: EngineBehavior]
    private var runningHostIdsByTaskId: [UUID: UUID] = [:]
    private(set) var startedTaskIds: [UUID] = []
    private(set) var maxRunningTotal = 0
    private(set) var maxRunningByHost: [UUID: Int] = [:]

    init(behaviors: [UUID: EngineBehavior] = [:]) {
        self.behaviors = behaviors
    }

    func setBehavior(_ behavior: EngineBehavior, for taskId: UUID) {
        behaviors[taskId] = behavior
    }

    func stats() -> EngineStats {
        EngineStats(maxRunningTotal: maxRunningTotal, maxRunningByHost: maxRunningByHost)
    }

    func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        startedTaskIds.append(task.id)
        runningHostIdsByTaskId[task.id] = task.hostId
        maxRunningTotal = max(maxRunningTotal, runningHostIdsByTaskId.count)
        let runningForHost = runningHostIdsByTaskId.values.filter { $0 == task.hostId }.count
        maxRunningByHost[task.hostId] = max(maxRunningByHost[task.hostId] ?? 0, runningForHost)
        defer {
            runningHostIdsByTaskId.removeValue(forKey: task.id)
        }

        switch behaviors[task.id] ?? .succeed([]) {
        case .succeed(let events):
            for event in events {
                await progress(event)
            }
        case .fail(let message):
            throw ScriptedEngineError(message: message)
        case .block:
            while true {
                try Task.checkCancellation()
                try await Task.sleep(nanoseconds: 10_000_000)
            }
        }
    }
}

private struct EngineStats: Sendable {
    let maxRunningTotal: Int
    let maxRunningByHost: [UUID: Int]
}

private final class InMemoryTransferHistoryStore: TransferHistoryStore, @unchecked Sendable {
    private let lock = NSLock()
    private var tasks: [TransferTask]
    private var snapshots: [[TransferTask]] = []

    init(initialTasks: [TransferTask] = []) {
        self.tasks = initialTasks
    }

    var savedSnapshots: [[TransferTask]] {
        get async {
            lock.withLock { snapshots }
        }
    }

    func load() throws -> [TransferTask] {
        lock.withLock { tasks }
    }

    func save(_ tasks: [TransferTask]) throws {
        lock.withLock {
            self.tasks = tasks
            snapshots.append(tasks)
        }
    }
}

private func makeTask(
    id: UUID = UUID(),
    hostId: UUID = UUID(),
    direction: TransferDirection = .upload,
    fileName: String = "file.txt",
    totalBytes: UInt64? = 10,
    status: TransferStatus = .pending,
    startedAt: Date? = nil,
    completedAt: Date? = nil
) -> TransferTask {
    TransferTask(
        id: id,
        hostId: hostId,
        hostDisplayName: "dev",
        direction: direction,
        localPath: "/Users/me/\(fileName)",
        remotePath: "/home/ubuntu/\(fileName)",
        fileName: fileName,
        totalBytes: totalBytes,
        status: status,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000),
        startedAt: startedAt,
        completedAt: completedAt
    )
}

private func fixedNow() -> Date {
    Date(timeIntervalSince1970: 1_800_000_000)
}

private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition")
}
