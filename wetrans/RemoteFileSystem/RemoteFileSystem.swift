import Foundation

public struct RemoteSession: Identifiable, Equatable {
    public let id: UUID
    public let hostId: UUID
    public let displayName: String
    public let connectedAt: Date

    public init(id: UUID = UUID(), hostId: UUID, displayName: String, connectedAt: Date = Date()) {
        self.id = id
        self.hostId = hostId
        self.displayName = displayName
        self.connectedAt = connectedAt
    }
}

public enum RemoteFileSystemError: Error, Equatable {
    case connectionFailed(String)
    case disconnected
    case notDirectory(String)
    case permissionDenied(String)
}

public protocol RemoteFileSystem {
    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
}

