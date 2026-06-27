import Foundation

public protocol LibSSH2Client: AnyObject {
    func connect(_ spec: ConnectionSpec) throws
    func hostKey(hostId: UUID, hostname: String, port: Int, at date: Date) throws -> TrustedHostKey
    func authenticate(username: String, auth: ConnectionAuth) throws
    func openSFTP() throws
    func listDirectory(_ path: String) throws -> [FileItem]
    func ensureDirectory(_ path: String) throws
    func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
    func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
    func disconnect()
}

public protocol LibSSH2ClientFactory {
    func makeClient() -> LibSSH2Client
}

public final class DefaultLibSSH2ClientFactory: LibSSH2ClientFactory {
    private let runtime: LibSSH2RuntimeManaging

    public init(runtime: LibSSH2RuntimeManaging = LibSSH2Runtime()) {
        self.runtime = runtime
    }

    public func makeClient() -> LibSSH2Client {
        LibSSH2DynamicClient(runtime: runtime)
    }
}
