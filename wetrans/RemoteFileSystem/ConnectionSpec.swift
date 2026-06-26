import Foundation

public enum ConnectionAuth: Equatable {
    case password(String?)
    case sshKey(identityFile: String, passphrase: String?)
}

public enum ConnectionSpecError: Error, Equatable {
    case missingIdentityFile(hostId: UUID)
}

public struct ConnectionSpec: Equatable {
    public let hostId: UUID
    public let displayName: String
    public let hostname: String
    public let port: Int
    public let username: String
    public let auth: ConnectionAuth
    public let defaultRemotePath: String

    public init(
        hostId: UUID,
        displayName: String,
        hostname: String,
        port: Int,
        username: String,
        auth: ConnectionAuth,
        defaultRemotePath: String
    ) {
        self.hostId = hostId
        self.displayName = displayName
        self.hostname = hostname
        self.port = port
        self.username = username
        self.auth = auth
        self.defaultRemotePath = defaultRemotePath
    }

    public static func make(host: SavedHost, credentialStore: CredentialStore) throws -> ConnectionSpec {
        let auth: ConnectionAuth
        switch host.authType {
        case .password:
            auth = .password(try credentialStore.loadPassword(hostId: host.id))
        case .sshKey:
            guard let identityFile = host.identityFile?.trimmedNilIfEmpty else {
                throw ConnectionSpecError.missingIdentityFile(hostId: host.id)
            }
            auth = .sshKey(
                identityFile: identityFile,
                passphrase: try credentialStore.loadKeyPassphrase(hostId: host.id)
            )
        }

        return ConnectionSpec(
            hostId: host.id,
            displayName: host.displayName,
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            auth: auth,
            defaultRemotePath: host.lastRemotePath?.trimmedNilIfEmpty
                ?? host.defaultRemotePath?.trimmedNilIfEmpty
                ?? "."
        )
    }
}
