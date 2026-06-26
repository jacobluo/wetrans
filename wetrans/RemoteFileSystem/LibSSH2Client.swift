import Foundation

public protocol LibSSH2Client: AnyObject {
    func connect(_ spec: ConnectionSpec) throws
    func hostKey(hostId: UUID, hostname: String, port: Int, at date: Date) throws -> TrustedHostKey
    func authenticate(username: String, auth: ConnectionAuth) throws
    func openSFTP() throws
    func listDirectory(_ path: String) throws -> [FileItem]
    func disconnect()
}

public protocol LibSSH2ClientFactory {
    func makeClient() -> LibSSH2Client
}

public final class DefaultLibSSH2ClientFactory: LibSSH2ClientFactory {
    public init() {}

    public func makeClient() -> LibSSH2Client {
        UnsupportedLibSSH2Client()
    }
}

private final class UnsupportedLibSSH2Client: LibSSH2Client {
    func connect(_ spec: ConnectionSpec) throws {
        throw LibSSH2Error.operationUnsupported("libssh2 dynamic client is not implemented yet")
    }

    func hostKey(hostId: UUID, hostname: String, port: Int, at date: Date) throws -> TrustedHostKey {
        throw LibSSH2Error.operationUnsupported("libssh2 dynamic client is not implemented yet")
    }

    func authenticate(username: String, auth: ConnectionAuth) throws {
        throw LibSSH2Error.operationUnsupported("libssh2 dynamic client is not implemented yet")
    }

    func openSFTP() throws {
        throw LibSSH2Error.operationUnsupported("libssh2 dynamic client is not implemented yet")
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        throw LibSSH2Error.operationUnsupported("libssh2 dynamic client is not implemented yet")
    }

    func disconnect() {}
}
