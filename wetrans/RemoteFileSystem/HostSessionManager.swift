import Foundation

public final class HostSessionManager {
    private let remoteFileSystem: RemoteFileSystem
    private let credentialStore: CredentialStore
    private let defaultLocalPath: () -> String
    private var states: [UUID: HostSessionState] = [:]
    private var sessions: [UUID: RemoteSession] = [:]

    public init(
        remoteFileSystem: RemoteFileSystem,
        credentialStore: CredentialStore,
        defaultLocalPath: @escaping () -> String = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
    ) {
        self.remoteFileSystem = remoteFileSystem
        self.credentialStore = credentialStore
        self.defaultLocalPath = defaultLocalPath
    }

    public func state(for host: SavedHost) -> HostSessionState {
        state(for: host.id) ?? makeInitialState(for: host)
    }

    public func updateLocalPath(_ path: String, for host: SavedHost) {
        var hostState = state(for: host)
        hostState.currentLocalPath = path
        hostState.lastActiveAt = Date()
        states[host.id] = hostState
    }

    public func updateRemotePath(_ path: String, for host: SavedHost) {
        var hostState = state(for: host)
        hostState.currentRemotePath = path
        hostState.lastActiveAt = Date()
        states[host.id] = hostState
    }

    public func listRemoteDirectory(for host: SavedHost) async throws -> [FileItem] {
        var hostState = state(for: host)
        let session = try await session(for: host)
        let items = try await remoteFileSystem.listDirectory(hostState.currentRemotePath, in: session)
        hostState.isConnected = true
        hostState.lastActiveAt = Date()
        states[host.id] = hostState
        return items
    }

    public func disconnect(hostId: UUID) async {
        if let session = sessions.removeValue(forKey: hostId) {
            await remoteFileSystem.disconnect(session)
        }
        if var hostState = states[hostId] {
            hostState.isConnected = false
            hostState.lastActiveAt = Date()
            states[hostId] = hostState
        }
    }

    private func session(for host: SavedHost) async throws -> RemoteSession {
        if let session = sessions[host.id] {
            return session
        }
        let spec = try ConnectionSpec.make(host: host, credentialStore: credentialStore)
        let session = try await remoteFileSystem.connect(spec)
        sessions[host.id] = session
        var hostState = state(for: host)
        hostState.isConnected = true
        hostState.lastActiveAt = Date()
        states[host.id] = hostState
        return session
    }

    private func state(for hostId: UUID) -> HostSessionState? {
        states[hostId]
    }

    private func makeInitialState(for host: SavedHost) -> HostSessionState {
        let initialState = HostSessionState(
            hostId: host.id,
            isConnected: false,
            currentRemotePath: host.lastRemotePath?.trimmedNilIfEmpty
                ?? host.defaultRemotePath?.trimmedNilIfEmpty
                ?? "~",
            currentLocalPath: host.lastLocalPath?.trimmedNilIfEmpty
                ?? defaultLocalPath()
        )
        states[host.id] = initialState
        return initialState
    }
}

