import Foundation

public struct TransferProgress: Equatable, Sendable {
    public let transferredBytes: UInt64
    public let totalBytes: UInt64?
    public let speedBytesPerSecond: UInt64?

    public init(
        transferredBytes: UInt64,
        totalBytes: UInt64?,
        speedBytesPerSecond: UInt64? = nil
    ) {
        self.transferredBytes = transferredBytes
        self.totalBytes = totalBytes
        self.speedBytesPerSecond = speedBytesPerSecond
    }
}

public protocol TransferEngine: Sendable {
    func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
}

public struct UnavailableTransferEngine: TransferEngine {
    public init() {}

    public func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        throw TransferQueueError.engineUnavailable
    }
}

public enum TransferQueueError: Error, LocalizedError, Equatable {
    case engineUnavailable

    public var errorDescription: String? {
        switch self {
        case .engineUnavailable:
            return "Transfer engine is not available yet."
        }
    }
}
