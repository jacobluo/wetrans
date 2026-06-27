import Foundation

public final class LibSSH2RemoteFileSystem: RemoteFileSystem, @unchecked Sendable {
    private let runtime: LibSSH2RuntimeManaging
    private let trustedHostStore: TrustedHostStore
    private let clientFactory: LibSSH2ClientFactory
    private let clientsLock = NSLock()
    private var clientsBySessionId: [UUID: LibSSH2Client] = [:]

    public init(
        runtime: LibSSH2RuntimeManaging = LibSSH2Runtime(),
        trustedHostStore: TrustedHostStore = LibSSH2RemoteFileSystem.makeDefaultTrustedHostStore(),
        clientFactory: LibSSH2ClientFactory? = nil
    ) {
        self.runtime = runtime
        self.trustedHostStore = trustedHostStore
        self.clientFactory = clientFactory ?? DefaultLibSSH2ClientFactory(runtime: runtime)
    }

    public static func makeDefaultTrustedHostStore() -> TrustedHostStore {
        FileTrustedHostStore(applicationSupportDirectory: FileManager.default.wetransApplicationSupportDirectory)
    }

    public func connect(_ spec: ConnectionSpec) async throws -> RemoteSession {
        _ = try runtime.initialize()

        let client = clientFactory.makeClient()
        do {
            try client.connect(spec)
            let now = Date()
            let candidate = try client.hostKey(
                hostId: spec.hostId,
                hostname: spec.hostname,
                port: spec.port,
                at: now
            )
            let trusted = try trustedHostStore.lookup(
                hostId: spec.hostId,
                hostname: spec.hostname,
                port: spec.port
            )

            switch HostKeyVerificationPolicy.decide(trusted: trusted, candidate: candidate) {
            case .trusted:
                try trustedHostStore.recordVerification(
                    hostId: spec.hostId,
                    hostname: spec.hostname,
                    port: spec.port,
                    at: now
                )
            case .requiresTrust(let candidate):
                throw RemoteFileSystemError.hostKeyRequiresTrust(candidate)
            case .blockedChangedKey(let expected, let actual):
                throw RemoteFileSystemError.hostKeyChanged(expected: expected, actual: actual)
            }

            try client.authenticate(username: spec.username, auth: spec.auth)
            try client.openSFTP()

            let session = RemoteSession(hostId: spec.hostId, displayName: spec.displayName)
            clientsLock.withLock {
                clientsBySessionId[session.id] = client
            }
            return session
        } catch {
            let isTrackedClient = clientsLock.withLock {
                clientsBySessionId.values.contains(where: { $0 === client })
            }
            if !isTrackedClient {
                client.disconnect()
            }
            throw error
        }
    }

    public func disconnect(_ session: RemoteSession) async {
        let result = clientsLock.withLock {
            guard let client = clientsBySessionId.removeValue(forKey: session.id) else {
                return nil as (client: LibSSH2Client, shouldShutdown: Bool)?
            }
            return (client, clientsBySessionId.isEmpty)
        }
        guard let result else {
            return
        }
        result.client.disconnect()
        if result.shouldShutdown {
            runtime.shutdown()
        }
    }

    public func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem] {
        guard let client = clientsLock.withLock({ clientsBySessionId[session.id] }) else {
            throw RemoteFileSystemError.disconnected
        }
        return try client.listDirectory(path)
    }

    public func upload(
        _ request: UploadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        guard let client = clientsLock.withLock({ clientsBySessionId[session.id] }) else {
            throw RemoteFileSystemError.disconnected
        }
        try await client.upload(request, progress: progress)
    }

    public func download(
        _ request: DownloadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        guard let client = clientsLock.withLock({ clientsBySessionId[session.id] }) else {
            throw RemoteFileSystemError.disconnected
        }
        try await client.download(request, progress: progress)
    }
}

private extension FileManager {
    var wetransApplicationSupportDirectory: URL {
        urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("wetrans", isDirectory: true)
    }
}
