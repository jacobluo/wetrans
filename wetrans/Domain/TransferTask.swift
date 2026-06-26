import Foundation

public enum TransferDirection: String, Codable, Equatable {
    case upload
    case download
}

public enum TransferStatus: String, Codable, Equatable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
    case paused
}

public struct TransferTask: Identifiable, Codable, Equatable {
    public let id: UUID
    public let hostId: UUID
    public let hostDisplayName: String
    public let direction: TransferDirection
    public let localPath: String
    public let remotePath: String
    public let fileName: String
    public let totalBytes: UInt64?
    public var transferredBytes: UInt64
    public var progress: Double
    public var speedBytesPerSecond: UInt64?
    public var status: TransferStatus
    public var errorMessage: String?
    public let createdAt: Date
    public var startedAt: Date?
    public var completedAt: Date?

    public init(
        id: UUID = UUID(),
        hostId: UUID,
        hostDisplayName: String,
        direction: TransferDirection,
        localPath: String,
        remotePath: String,
        fileName: String,
        totalBytes: UInt64?,
        transferredBytes: UInt64 = 0,
        progress: Double = 0,
        speedBytesPerSecond: UInt64? = nil,
        status: TransferStatus = .pending,
        errorMessage: String? = nil,
        createdAt: Date = Date(),
        startedAt: Date? = nil,
        completedAt: Date? = nil
    ) {
        self.id = id
        self.hostId = hostId
        self.hostDisplayName = hostDisplayName
        self.direction = direction
        self.localPath = localPath
        self.remotePath = remotePath
        self.fileName = fileName
        self.totalBytes = totalBytes
        self.transferredBytes = transferredBytes
        self.progress = progress
        self.speedBytesPerSecond = speedBytesPerSecond
        self.status = status
        self.errorMessage = errorMessage
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.completedAt = completedAt
    }
}

