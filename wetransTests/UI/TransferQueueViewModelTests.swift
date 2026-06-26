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

private func makeSummaryTask(
    direction: TransferDirection,
    status: TransferStatus,
    fileName: String
) -> TransferTask {
    TransferTask(
        hostId: UUID(),
        hostDisplayName: "dev",
        direction: direction,
        localPath: "/Users/me/\(fileName)",
        remotePath: "/home/ubuntu/\(fileName)",
        fileName: fileName,
        totalBytes: 10,
        status: status,
        createdAt: Date(timeIntervalSince1970: 1_700_000_000)
    )
}
