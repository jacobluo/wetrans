import XCTest
@testable import wetrans

@MainActor
final class TransferQueueViewModelTests: XCTestCase {
    func testRefreshShowsEmptySummary() async {
        let viewModel = TransferQueueViewModel(
            queue: TransferQueue(engine: UnavailableTransferEngine(), historyStore: TestTransferHistoryStore())
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.summary, .empty)
        XCTAssertEqual(viewModel.summaryText, "No transfers")
    }

    func testConcurrencyHintUsesQueueLimitsInsteadOfFixedCopy() {
        let viewModel = TransferQueueViewModel(
            queue: TransferQueue(
                engine: UnavailableTransferEngine(),
                historyStore: TestTransferHistoryStore(),
                globalConcurrencyLimit: 4,
                perHostConcurrencyLimit: 1
            )
        )

        XCTAssertEqual(
            viewModel.concurrencyHintText,
            "Up to 4 global · 1 per host · continues across host switching"
        )
        XCTAssertFalse(viewModel.concurrencyHintText.contains("running"))
        XCTAssertFalse(viewModel.concurrencyHintText.contains("survives"))
    }

    func testSettingConcurrencyLimitsUpdatesQueueAndHint() async {
        let queue = TransferQueue(
            engine: UnavailableTransferEngine(),
            historyStore: TestTransferHistoryStore(),
            globalConcurrencyLimit: 3,
            perHostConcurrencyLimit: 2
        )
        let viewModel = TransferQueueViewModel(queue: queue)

        await viewModel.setGlobalConcurrencyLimit(4)
        await viewModel.setPerHostConcurrencyLimit(1)

        let limits = await queue.concurrencyLimits()
        XCTAssertEqual(limits, TransferQueueConcurrencyLimits(global: 4, perHost: 1))
        XCTAssertEqual(viewModel.concurrencyHintText, "Up to 4 global · 1 per host · continues across host switching")
    }

    func testRefreshCountsTasksByDirectionAndStatus() async {
        let uploadRunning = makeSummaryTask(direction: .upload, status: .running, fileName: "upload.txt")
        let uploadPending = makeSummaryTask(direction: .upload, status: .pending, fileName: "pending.txt")
        let downloadFailed = makeSummaryTask(direction: .download, status: .failed, fileName: "download.log")
        let viewModel = TransferQueueViewModel(
            queue: TransferQueue(
                engine: UnavailableTransferEngine(),
                historyStore: TestTransferHistoryStore(initialTasks: [uploadRunning, uploadPending, downloadFailed])
            )
        )

        await viewModel.refresh()

        XCTAssertEqual(viewModel.summary.totalCount, 3)
        XCTAssertEqual(viewModel.summary.uploadCount, 2)
        XCTAssertEqual(viewModel.summary.downloadCount, 1)
        XCTAssertEqual(viewModel.summary.runningCount, 0)
        XCTAssertEqual(viewModel.summary.failedCount, 2)
        XCTAssertEqual(viewModel.summaryText, "3 transfers · Upload 2 · Download 1 · Failed 2")
    }

    func testRowsFormatTaskMetadataAndActions() async {
        let running = makeSummaryTask(
            direction: .upload,
            status: .running,
            fileName: "config.yaml",
            totalBytes: 100,
            transferredBytes: 72,
            progress: 0.72,
            speedBytesPerSecond: 1_200_000
        )
        let failed = makeSummaryTask(
            direction: .download,
            status: .failed,
            fileName: "model.bin",
            totalBytes: nil,
            transferredBytes: 0,
            progress: 0,
            errorMessage: "Permission denied"
        )
        let rows = [
            TransferQueueRowViewState(task: running),
            TransferQueueRowViewState(task: failed)
        ]

        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0].fileName, "config.yaml")
        XCTAssertEqual(rows[0].hostName, "dev")
        XCTAssertEqual(rows[0].directionText, "Upload")
        XCTAssertEqual(rows[0].progressText, "72%")
        XCTAssertEqual(rows[0].progressValue, 0.72)
        XCTAssertEqual(rows[0].bytesText, "\(byteText(72)) / \(byteText(100))")
        XCTAssertEqual(rows[0].statusText, "Running")
        XCTAssertEqual(rows[0].primaryAction, .cancel)
        XCTAssertEqual(rows[1].directionText, "Download")
        XCTAssertEqual(rows[1].statusText, "Failed")
        XCTAssertEqual(rows[1].primaryAction, .retry)
        XCTAssertEqual(rows[1].errorMessage, "Permission denied")
    }

    func testToggleExpandedAndQueueActionsRefreshRows() async throws {
        let failed = makeSummaryTask(status: .failed, fileName: "failed.txt", errorMessage: "No space left")
        let succeeded = makeSummaryTask(status: .succeeded, fileName: "done.txt")
        let engine = BlockingTransferEngine()
        let queue = TransferQueue(
            engine: engine,
            historyStore: TestTransferHistoryStore(initialTasks: [failed, succeeded])
        )
        let viewModel = TransferQueueViewModel(queue: queue)

        XCTAssertTrue(viewModel.isExpanded)
        viewModel.toggleExpanded()
        XCTAssertFalse(viewModel.isExpanded)

        await viewModel.refresh()
        await viewModel.remove(taskId: succeeded.id)
        XCTAssertEqual(viewModel.rows.map(\.id), [failed.id])

        await viewModel.retry(taskId: failed.id)
        try await waitUntil {
            await viewModel.refresh()
            return viewModel.rows.first?.statusText == "Running"
        }
        XCTAssertEqual(viewModel.rows.first?.statusText, "Running")

        await viewModel.cancel(taskId: failed.id)
        XCTAssertEqual(viewModel.rows.first?.statusText, "Cancelled")

        await viewModel.clearFailedAndCancelled()
        XCTAssertEqual(viewModel.rows, [])
    }
}

private final class TestTransferHistoryStore: TransferHistoryStore, @unchecked Sendable {
    private let tasks: [TransferTask]

    init(initialTasks: [TransferTask] = []) {
        self.tasks = initialTasks
    }

    func load() throws -> [TransferTask] {
        tasks
    }

    func save(_ tasks: [TransferTask]) throws {}
}

private actor BlockingTransferEngine: TransferEngine {
    func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        while true {
            try Task.checkCancellation()
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

private func makeSummaryTask(
    direction: TransferDirection = .upload,
    status: TransferStatus,
    fileName: String,
    totalBytes: UInt64? = 10,
    transferredBytes: UInt64 = 0,
    progress: Double = 0,
    speedBytesPerSecond: UInt64? = nil,
    errorMessage: String? = nil
) -> TransferTask {
    TransferTask(
        hostId: UUID(),
        hostDisplayName: "dev",
        direction: direction,
        localPath: "/Users/me/\(fileName)",
        remotePath: "/home/ubuntu/\(fileName)",
        fileName: fileName,
        totalBytes: totalBytes,
        transferredBytes: transferredBytes,
        progress: progress,
        speedBytesPerSecond: speedBytesPerSecond,
        status: status,
        errorMessage: errorMessage,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () async -> Bool
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

private func byteText(_ bytes: UInt64) -> String {
    let formatter = ByteCountFormatter()
    formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
    formatter.countStyle = .file
    return formatter.string(fromByteCount: Int64(bytes))
}
