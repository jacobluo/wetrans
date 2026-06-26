import Foundation

public final class LibSSH2RemoteFileSystem: RemoteFileSystem {
    private let runtime: LibSSH2RuntimeManaging

    public init(runtime: LibSSH2RuntimeManaging = LibSSH2Runtime()) {
        self.runtime = runtime
    }

    public func connect(_ spec: ConnectionSpec) async throws -> RemoteSession {
        _ = try runtime.initialize()
        throw LibSSH2Error.operationUnsupported("libssh2 SFTP connect is not implemented yet")
    }

    public func disconnect(_ session: RemoteSession) async {
        runtime.shutdown()
    }

    public func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem] {
        throw RemoteFileSystemError.disconnected
    }
}
