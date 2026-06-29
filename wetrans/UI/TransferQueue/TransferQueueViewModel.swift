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

public enum TransferQueueRowAction: Equatable, Sendable {
    case cancel
    case retry
    case remove
}

public struct TransferQueueRowViewState: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let fileName: String
    public let hostName: String
    public let directionText: String
    public let progressValue: Double
    public let progressText: String
    public let bytesText: String
    public let speedText: String
    public let statusText: String
    public let errorMessage: String?
    public let primaryAction: TransferQueueRowAction?
    public let canRemove: Bool
    public let isFailed: Bool

    public init(task: TransferTask) {
        self.id = task.id
        self.fileName = task.fileName
        self.hostName = task.hostDisplayName
        self.directionText = task.direction.displayText
        self.progressValue = task.progress.clamped(to: 0...1)
        self.progressText = "\(Int((progressValue * 100).rounded()).clamped(to: 0...100))%"
        self.bytesText = Self.bytesText(transferred: task.transferredBytes, total: task.totalBytes)
        self.speedText = task.speedBytesPerSecond.map { Self.byteText($0) + "/s" } ?? "-"
        self.statusText = task.status.displayText
        self.errorMessage = task.errorMessage
        self.primaryAction = task.status.primaryAction
        self.canRemove = task.status.isTerminal
        self.isFailed = task.status == .failed
    }

    private static func bytesText(transferred: UInt64, total: UInt64?) -> String {
        let transferredText = byteText(transferred)
        guard let total else {
            return transferredText
        }
        return "\(transferredText) / \(byteText(total))"
    }

    private static func byteText(_ bytes: UInt64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useBytes, .useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: Int64(bytes))
    }
}

@MainActor
public final class TransferQueueViewModel: ObservableObject {
    @Published public private(set) var summary: TransferQueueSummary = .empty
    @Published public private(set) var rows: [TransferQueueRowViewState] = []
    @Published public private(set) var concurrencyLimits: TransferQueueConcurrencyLimits
    @Published public var isExpanded = true

    private let queue: TransferQueue

    public init(queue: TransferQueue) {
        self.queue = queue
        self.concurrencyLimits = queue.initialConcurrencyLimits
    }

    public var concurrencyHintText: String {
        concurrencyLimits.hintText
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
        let tasks = await queue.snapshot()
        concurrencyLimits = await queue.concurrencyLimits()
        summary = TransferQueueSummary(tasks: tasks)
        rows = tasks.map(TransferQueueRowViewState.init)
    }

    public func setGlobalConcurrencyLimit(_ value: Int) async {
        await setConcurrencyLimits(TransferQueueConcurrencyLimits(global: value, perHost: concurrencyLimits.perHost))
    }

    public func setPerHostConcurrencyLimit(_ value: Int) async {
        await setConcurrencyLimits(TransferQueueConcurrencyLimits(global: concurrencyLimits.global, perHost: value))
    }

    private func setConcurrencyLimits(_ limits: TransferQueueConcurrencyLimits) async {
        await queue.updateConcurrencyLimits(limits)
        concurrencyLimits = await queue.concurrencyLimits()
        await refresh()
    }

    public func toggleExpanded() {
        isExpanded.toggle()
    }

    public func cancel(taskId: UUID) async {
        await queue.cancel(taskId: taskId)
        await refresh()
    }

    public func retry(taskId: UUID) async {
        await queue.retry(taskId: taskId)
        await refresh()
    }

    public func remove(taskId: UUID) async {
        await queue.removeFinished(taskId: taskId)
        await refresh()
    }

    public func clearSucceeded() async {
        await queue.clearFinished(statuses: [.succeeded])
        await refresh()
    }

    public func clearFailedAndCancelled() async {
        await queue.clearFinished(statuses: [.failed, .cancelled])
        await refresh()
    }

    public func clearFinished() async {
        await queue.clearFinished()
        await refresh()
    }
}

private extension TransferQueueConcurrencyLimits {
    var hintText: String {
        "Up to \(global) global · \(perHost) per host · continues across host switching"
    }
}

private extension TransferDirection {
    var displayText: String {
        switch self {
        case .upload:
            return "Upload"
        case .download:
            return "Download"
        }
    }
}

private extension TransferStatus {
    var displayText: String {
        switch self {
        case .pending:
            return "Pending"
        case .running:
            return "Running"
        case .succeeded:
            return "Succeeded"
        case .failed:
            return "Failed"
        case .cancelled:
            return "Cancelled"
        case .paused:
            return "Paused"
        }
    }

    var primaryAction: TransferQueueRowAction? {
        switch self {
        case .pending, .running:
            return .cancel
        case .failed, .cancelled:
            return .retry
        case .succeeded:
            return .remove
        case .paused:
            return nil
        }
    }

    var isTerminal: Bool {
        switch self {
        case .succeeded, .failed, .cancelled:
            return true
        case .pending, .running, .paused:
            return false
        }
    }
}

private extension Int {
    func clamped(to range: ClosedRange<Int>) -> Int {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}

private extension Double {
    func clamped(to range: ClosedRange<Double>) -> Double {
        Swift.min(Swift.max(self, range.lowerBound), range.upperBound)
    }
}
