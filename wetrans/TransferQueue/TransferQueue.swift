import Foundation

public struct TransferQueueConcurrencyLimits: Codable, Equatable, Sendable {
    public let global: Int
    public let perHost: Int

    public init(global: Int, perHost: Int) {
        self.global = max(1, global)
        self.perHost = max(1, perHost)
    }
}

public actor TransferQueue {
    public nonisolated let initialConcurrencyLimits: TransferQueueConcurrencyLimits

    private let engine: TransferEngine
    private let historyStore: TransferHistoryStore
    private let settingsStore: TransferQueueSettingsStore
    private let now: @Sendable () -> Date
    private var currentConcurrencyLimits: TransferQueueConcurrencyLimits

    private var tasks: [TransferTask]
    private var runningJobs: [UUID: Task<Void, Never>] = [:]
    private var eventContinuations: [UUID: AsyncStream<TransferQueueEvent>.Continuation] = [:]
    private var lastPersistenceErrorMessage: String?

    public init(
        engine: TransferEngine,
        historyStore: TransferHistoryStore = EmptyTransferHistoryStore(),
        settingsStore: TransferQueueSettingsStore = EmptyTransferQueueSettingsStore(),
        globalConcurrencyLimit: Int = 3,
        perHostConcurrencyLimit: Int = 2,
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        let fallbackLimits = TransferQueueConcurrencyLimits(
            global: globalConcurrencyLimit,
            perHost: perHostConcurrencyLimit
        )
        let loadedLimits = (try? settingsStore.load())?.concurrencyLimits ?? fallbackLimits
        self.initialConcurrencyLimits = loadedLimits
        self.currentConcurrencyLimits = loadedLimits
        self.engine = engine
        self.historyStore = historyStore
        self.settingsStore = settingsStore
        self.now = now

        let loadedTasks = (try? historyStore.load()) ?? []
        let startupDate = now()
        self.tasks = loadedTasks.map { task in
            guard task.status == .running else {
                return task
            }

            var interrupted = task
            interrupted.status = .failed
            interrupted.errorMessage = "Transfer interrupted because wetrans was closed."
            interrupted.completedAt = startupDate
            return interrupted
        }

        if loadedTasks != self.tasks {
            try? historyStore.save(self.tasks)
        }
    }

    public func snapshot() -> [TransferTask] {
        tasks
    }

    public func concurrencyLimits() -> TransferQueueConcurrencyLimits {
        currentConcurrencyLimits
    }

    public func updateConcurrencyLimits(_ limits: TransferQueueConcurrencyLimits) {
        currentConcurrencyLimits = limits
        do {
            try settingsStore.save(TransferQueueSettings(concurrencyLimits: limits))
        } catch {
            lastPersistenceErrorMessage = error.localizedDescription
        }
        schedule()
    }

    public func lastPersistenceError() -> String? {
        lastPersistenceErrorMessage
    }

    public func events() -> AsyncStream<TransferQueueEvent> {
        let id = UUID()
        return AsyncStream { continuation in
            eventContinuations[id] = continuation
            continuation.onTermination = { [weak self] _ in
                Task {
                    await self?.removeEventContinuation(id: id)
                }
            }
        }
    }

    public func enqueue(_ newTasks: [TransferTask]) {
        guard !newTasks.isEmpty else {
            return
        }

        tasks.append(contentsOf: newTasks.map { task in
            var pending = task
            pending.status = .pending
            pending.transferredBytes = 0
            pending.progress = 0
            pending.speedBytesPerSecond = nil
            pending.errorMessage = nil
            pending.startedAt = nil
            pending.completedAt = nil
            return pending
        })
        persist()
        schedule()
    }

    public func cancel(taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            return
        }

        switch tasks[index].status {
        case .pending:
            markCancelled(at: index)
        case .running:
            let job = runningJobs.removeValue(forKey: taskId)
            markCancelled(at: index)
            job?.cancel()
        case .succeeded, .failed, .cancelled, .paused:
            return
        }

        persist()
        schedule()
    }

    public func retry(taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            return
        }
        guard tasks[index].status == .failed || tasks[index].status == .cancelled else {
            return
        }

        tasks[index].status = .pending
        tasks[index].transferredBytes = 0
        tasks[index].progress = 0
        tasks[index].speedBytesPerSecond = nil
        tasks[index].errorMessage = nil
        tasks[index].startedAt = nil
        tasks[index].completedAt = nil
        persist()
        schedule()
    }

    public func clearFinished(statuses: Set<TransferStatus> = [.succeeded, .failed, .cancelled]) {
        let clearable = statuses.subtracting([.pending, .running])
        tasks.removeAll { clearable.contains($0.status) }
        persist()
        schedule()
    }

    public func removeFinished(taskId: UUID) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            return
        }
        guard [.succeeded, .failed, .cancelled].contains(tasks[index].status) else {
            return
        }

        tasks.remove(at: index)
        persist()
        schedule()
    }

    private func schedule() {
        var runningTotal = tasks.filter { $0.status == .running }.count
        var runningByHost = tasks
            .filter { $0.status == .running }
            .reduce(into: [UUID: Int]()) { counts, task in
                counts[task.hostId, default: 0] += 1
            }

        for index in tasks.indices where tasks[index].status == .pending {
            guard runningTotal < currentConcurrencyLimits.global else {
                break
            }
            let hostId = tasks[index].hostId
            guard (runningByHost[hostId] ?? 0) < currentConcurrencyLimits.perHost else {
                continue
            }

            tasks[index].status = .running
            tasks[index].startedAt = now()
            tasks[index].completedAt = nil
            tasks[index].errorMessage = nil
            let taskSnapshot = tasks[index]
            runningTotal += 1
            runningByHost[hostId, default: 0] += 1
            persist()

            runningJobs[taskSnapshot.id] = Task.detached { [engine] in
                do {
                    try await engine.run(task: taskSnapshot) { progress in
                        await self.updateProgress(taskId: taskSnapshot.id, progress: progress)
                    }
                    await self.finish(taskId: taskSnapshot.id)
                } catch is CancellationError {
                    await self.finishCancelledIfRunning(taskId: taskSnapshot.id)
                } catch {
                    await self.fail(taskId: taskSnapshot.id, error: error)
                }
            }
        }
    }

    private func updateProgress(taskId: UUID, progress: TransferProgress) {
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            return
        }
        guard tasks[index].status == .running else {
            return
        }

        tasks[index].transferredBytes = progress.transferredBytes
        tasks[index].speedBytesPerSecond = progress.speedBytesPerSecond
        let totalBytes = progress.totalBytes ?? tasks[index].totalBytes
        if let totalBytes, totalBytes > 0 {
            tasks[index].progress = min(1, Double(progress.transferredBytes) / Double(totalBytes))
        }
        persist()
    }

    private func finish(taskId: UUID) {
        runningJobs.removeValue(forKey: taskId)
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            schedule()
            return
        }
        guard tasks[index].status == .running else {
            schedule()
            return
        }

        if let totalBytes = tasks[index].totalBytes {
            tasks[index].transferredBytes = totalBytes
        }
        tasks[index].progress = 1
        tasks[index].status = .succeeded
        tasks[index].errorMessage = nil
        tasks[index].completedAt = now()
        persist()
        emit(TransferQueueEvent(task: tasks[index]))
        schedule()
    }

    private func fail(taskId: UUID, error: Error) {
        runningJobs.removeValue(forKey: taskId)
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            schedule()
            return
        }
        guard tasks[index].status == .running else {
            schedule()
            return
        }

        tasks[index].status = .failed
        tasks[index].errorMessage = Self.message(for: error)
        tasks[index].speedBytesPerSecond = nil
        tasks[index].completedAt = now()
        persist()
        schedule()
    }

    private func finishCancelledIfRunning(taskId: UUID) {
        runningJobs.removeValue(forKey: taskId)
        guard let index = tasks.firstIndex(where: { $0.id == taskId }) else {
            schedule()
            return
        }
        guard tasks[index].status == .running else {
            schedule()
            return
        }

        markCancelled(at: index)
        persist()
        schedule()
    }

    private func markCancelled(at index: Int) {
        tasks[index].status = .cancelled
        tasks[index].speedBytesPerSecond = nil
        tasks[index].errorMessage = nil
        tasks[index].completedAt = now()
    }

    private func persist() {
        do {
            try historyStore.save(tasks)
            lastPersistenceErrorMessage = nil
        } catch {
            lastPersistenceErrorMessage = Self.message(for: error)
        }
    }

    private func removeEventContinuation(id: UUID) {
        eventContinuations.removeValue(forKey: id)
    }

    private func emit(_ event: TransferQueueEvent) {
        for continuation in eventContinuations.values {
            continuation.yield(event)
        }
    }

    private static func message(for error: Error) -> String {
        if let localizedError = error as? LocalizedError, let description = localizedError.errorDescription {
            return description
        }
        return error.localizedDescription
    }
}
