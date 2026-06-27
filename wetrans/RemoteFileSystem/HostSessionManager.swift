import Foundation

public final class HostSessionManager: @unchecked Sendable {
    private let remoteFileSystem: RemoteFileSystem
    private let credentialStore: CredentialStore
    private let defaultLocalPath: () -> String
    private let now: @Sendable () -> Date
    private let lock = NSLock()
    private var states: [UUID: HostSessionState] = [:]
    private var sessions: [UUID: RemoteSession] = [:]
    private var pendingSessions: [UUID: Task<RemoteSession, Error>] = [:]

    public init(
        remoteFileSystem: RemoteFileSystem,
        credentialStore: CredentialStore,
        defaultLocalPath: @escaping () -> String = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.remoteFileSystem = remoteFileSystem
        self.credentialStore = credentialStore
        self.defaultLocalPath = defaultLocalPath
        self.now = now
    }

    public func state(for host: SavedHost) -> HostSessionState {
        lock.withLock {
            stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
        }
    }

    public func updateLocalPath(_ path: String, for host: SavedHost) {
        lock.withLock {
            var hostState = stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
            hostState.currentLocalPath = path
            hostState.lastActiveAt = now()
            states[host.id] = hostState
        }
    }

    public func updateRemotePath(_ path: String, for host: SavedHost) {
        lock.withLock {
            var hostState = stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
            hostState.currentRemotePath = path
            hostState.lastActiveAt = now()
            states[host.id] = hostState
        }
    }

    public func listRemoteDirectory(for host: SavedHost) async throws -> [FileItem] {
        let path = lock.withLock {
            let hostState = stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
            return hostState.currentRemotePath
        }
        return try await listRemoteDirectory(path: path, for: host)
    }

    public func listRemoteDirectory(path: String, for host: SavedHost) async throws -> [FileItem] {
        let cachedSession = lock.withLock {
            sessions[host.id]
        }
        let activeSession = try await session(for: host)
        do {
            return try await listRemoteDirectory(path, session: activeSession, host: host)
        } catch RemoteFileSystemError.connectionFailed where cachedSession?.id == activeSession.id {
            await removeCachedSession(activeSession, for: host.id)
            let retrySession = try await session(for: host)
            return try await listRemoteDirectory(path, session: retrySession, host: host)
        }
    }

    private func listRemoteDirectory(_ path: String, session: RemoteSession, host: SavedHost) async throws -> [FileItem] {
        let items = try await remoteFileSystem.listDirectory(path, in: session)
        lock.withLock {
            var hostState = stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
            hostState.isConnected = true
            hostState.lastActiveAt = now()
            states[host.id] = hostState
        }
        return items
    }

    private func removeCachedSession(_ session: RemoteSession, for hostId: UUID) async {
        let removedSession = lock.withLock {
            guard sessions[hostId]?.id == session.id else {
                return nil as RemoteSession?
            }
            return sessions.removeValue(forKey: hostId)
        }
        guard let removedSession else {
            return
        }

        await remoteFileSystem.disconnect(removedSession)

        lock.withLock {
            if var hostState = states[hostId] {
                hostState.isConnected = false
                hostState.lastActiveAt = now()
                states[hostId] = hostState
            }
        }
    }

    public func disconnect(hostId: UUID) async {
        let pendingSession = lock.withLock {
            pendingSessions.removeValue(forKey: hostId)
        }
        pendingSession?.cancel()

        let session = lock.withLock {
            sessions.removeValue(forKey: hostId)
        }
        if let session {
            await remoteFileSystem.disconnect(session)
        }
        lock.withLock {
            if var hostState = states[hostId] {
                hostState.isConnected = false
                hostState.lastActiveAt = now()
                states[hostId] = hostState
            }
        }
    }

    private func session(for host: SavedHost) async throws -> RemoteSession {
        if let session = lock.withLock({ sessions[host.id] }) {
            return session
        }
        let spec = try ConnectionSpec.make(host: host, credentialStore: credentialStore)
        if let session = lock.withLock({ sessions[host.id] }) {
            return session
        }

        let task: Task<RemoteSession, Error> = lock.withLock {
            if let pendingSession = pendingSessions[host.id] {
                return pendingSession
            }
            let pendingSession = Task<RemoteSession, Error> {
                try await remoteFileSystem.connect(spec)
            }
            pendingSessions[host.id] = pendingSession
            return pendingSession
        }

        do {
            let session = try await task.value
            return lock.withLock {
                pendingSessions.removeValue(forKey: host.id)
                if let existingSession = sessions[host.id] {
                    return existingSession
                }
                sessions[host.id] = session
                var hostState = stateUnlocked(for: host.id) ?? makeInitialStateUnlocked(for: host)
                hostState.isConnected = true
                hostState.lastActiveAt = now()
                states[host.id] = hostState
                return session
            }
        } catch {
            _ = lock.withLock {
                pendingSessions.removeValue(forKey: host.id)
            }
            throw error
        }
    }

    private func stateUnlocked(for hostId: UUID) -> HostSessionState? {
        states[hostId]
    }

    private func makeInitialStateUnlocked(for host: SavedHost) -> HostSessionState {
        let initialState = HostSessionState(
            hostId: host.id,
            isConnected: false,
            currentRemotePath: host.lastRemotePath?.trimmedNilIfEmpty
                ?? host.defaultRemotePath?.trimmedNilIfEmpty
                ?? ".",
            currentLocalPath: host.lastLocalPath?.trimmedNilIfEmpty
                ?? defaultLocalPath()
        )
        states[host.id] = initialState
        return initialState
    }

    public func disconnectIdleSessions(now: Date = Date(), idleTimeout: TimeInterval = 15 * 60) async {
        let expiredSessions = lock.withLock {
            let expired = sessions.compactMap { hostId, session -> (hostId: UUID, session: RemoteSession)? in
                guard let lastActiveAt = states[hostId]?.lastActiveAt else {
                    return nil
                }
                guard now.timeIntervalSince(lastActiveAt) >= idleTimeout else {
                    return nil
                }
                return (hostId, session)
            }
            for expiredSession in expired {
                sessions.removeValue(forKey: expiredSession.hostId)
            }
            return expired
        }

        for expired in expiredSessions {
            await remoteFileSystem.disconnect(expired.session)
            lock.withLock {
                if var hostState = states[expired.hostId] {
                    hostState.isConnected = false
                    hostState.lastActiveAt = now
                    states[expired.hostId] = hostState
                }
            }
        }
    }
}

extension HostSessionManager: HostSessionCleaning {}
