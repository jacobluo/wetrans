import Foundation

public enum SFTPTransferEngineError: Error, Equatable, LocalizedError {
    case hostNotFound(UUID)

    public var errorDescription: String? {
        switch self {
        case .hostNotFound(let hostId):
            return "Cannot find host for transfer task: \(hostId.uuidString)"
        }
    }
}

public protocol TransferConnectionProvider: Sendable {
    func connect(hostId: UUID) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
}

public final class HostCatalogTransferConnectionProvider: TransferConnectionProvider, @unchecked Sendable {
    private let hostCatalog: HostCatalog
    private let credentialStore: CredentialStore
    private let remoteFileSystem: RemoteFileSystem

    public init(
        hostCatalog: HostCatalog,
        credentialStore: CredentialStore,
        remoteFileSystem: RemoteFileSystem
    ) {
        self.hostCatalog = hostCatalog
        self.credentialStore = credentialStore
        self.remoteFileSystem = remoteFileSystem
    }

    public func connect(hostId: UUID) async throws -> RemoteSession {
        guard let host = try hostCatalog.load().first(where: { $0.id == hostId }) else {
            throw SFTPTransferEngineError.hostNotFound(hostId)
        }
        return try await remoteFileSystem.connect(ConnectionSpec.make(host: host, credentialStore: credentialStore))
    }

    public func disconnect(_ session: RemoteSession) async {
        await remoteFileSystem.disconnect(session)
    }
}

public struct SFTPTransferEngine: TransferEngine {
    private let connectionProvider: TransferConnectionProvider
    private let remoteFileSystem: RemoteFileSystem

    public init(
        connectionProvider: TransferConnectionProvider,
        remoteFileSystem: RemoteFileSystem
    ) {
        self.connectionProvider = connectionProvider
        self.remoteFileSystem = remoteFileSystem
    }

    public func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        let session = try await connectionProvider.connect(hostId: task.hostId)
        do {
            switch task.direction {
            case .upload:
                try await remoteFileSystem.ensureDirectory(
                    BrowserPath.remoteParent(of: task.remotePath),
                    in: session
                )
                try await remoteFileSystem.upload(
                    UploadRequest(localPath: task.localPath, remotePath: task.remotePath),
                    in: session,
                    progress: progress
                )
            case .download:
                try await remoteFileSystem.download(
                    DownloadRequest(remotePath: task.remotePath, localPath: task.localPath),
                    in: session,
                    progress: progress
                )
            }
            await connectionProvider.disconnect(session)
        } catch {
            await connectionProvider.disconnect(session)
            throw error
        }
    }
}
