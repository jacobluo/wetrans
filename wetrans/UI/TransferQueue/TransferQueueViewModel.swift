import Foundation

public struct TransferQueueSummary: Equatable, Sendable {
    public static let empty = TransferQueueSummary(
        totalCount: 0,
        uploadCount: 0,
        downloadCount: 0,
        runningCount: 0,
        failedCount: 0
    )

    public let totalCount: Int
    public let uploadCount: Int
    public let downloadCount: Int
    public let runningCount: Int
    public let failedCount: Int

    public init(
        totalCount: Int,
        uploadCount: Int,
        downloadCount: Int,
        runningCount: Int,
        failedCount: Int
    ) {
        self.totalCount = totalCount
        self.uploadCount = uploadCount
        self.downloadCount = downloadCount
        self.runningCount = runningCount
        self.failedCount = failedCount
    }

    public init(tasks: [TransferTask]) {
        self.init(
            totalCount: tasks.count,
            uploadCount: tasks.filter { $0.direction == .upload }.count,
            downloadCount: tasks.filter { $0.direction == .download }.count,
            runningCount: tasks.filter { $0.status == .running }.count,
            failedCount: tasks.filter { $0.status == .failed }.count
        )
    }
}

@MainActor
public final class TransferQueueViewModel: ObservableObject {
    @Published public private(set) var summary: TransferQueueSummary = .empty

    private let queue: TransferQueue

    public init(queue: TransferQueue) {
        self.queue = queue
    }

    public var summaryText: String {
        guard summary.totalCount > 0 else {
            return "No transfers"
        }

        var parts = ["\(summary.totalCount) transfers"]
        if summary.uploadCount > 0 {
            parts.append("Upload \(summary.uploadCount)")
        }
        if summary.downloadCount > 0 {
            parts.append("Download \(summary.downloadCount)")
        }
        if summary.runningCount > 0 {
            parts.append("Running \(summary.runningCount)")
        }
        if summary.failedCount > 0 {
            parts.append("Failed \(summary.failedCount)")
        }
        return parts.joined(separator: " · ")
    }

    public func refresh() async {
        summary = TransferQueueSummary(tasks: await queue.snapshot())
    }
}
