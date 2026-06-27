import Foundation

public struct RemoteSession: Identifiable, Equatable, Sendable {
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

public enum RemoteFileSystemError: Error, Equatable, LocalizedError {
    case connectionFailed(String)
    case disconnected
    case hostKeyRequiresTrust(TrustedHostKey)
    case hostKeyChanged(expected: TrustedHostKey, actual: TrustedHostKey)
    case notDirectory(String)
    case permissionDenied(String)

    public var errorDescription: String? {
        switch self {
        case .connectionFailed(let message):
            return message
        case .disconnected:
            return "Remote connection is disconnected. Refresh to retry."
        case .hostKeyRequiresTrust:
            return "Host key requires confirmation before browsing."
        case .hostKeyChanged:
            return "Host key changed. Remote browsing is blocked."
        case .notDirectory(let path):
            return "Not a remote directory: \(path)"
        case .permissionDenied(let path):
            return "Permission denied: \(path)"
        }
    }
}

public protocol RemoteFileSystem: Sendable {
    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
    func ensureDirectory(_ path: String, in session: RemoteSession) async throws
    func upload(
        _ request: UploadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
    func download(
        _ request: DownloadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
}
