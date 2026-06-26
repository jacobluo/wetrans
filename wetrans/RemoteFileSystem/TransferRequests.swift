import Foundation

public struct UploadRequest: Equatable, Sendable {
    public let localPath: String
    public let remotePath: String

    public init(localPath: String, remotePath: String) {
        self.localPath = localPath
        self.remotePath = remotePath
    }
}

public struct DownloadRequest: Equatable, Sendable {
    public let remotePath: String
    public let localPath: String

    public init(remotePath: String, localPath: String) {
        self.remotePath = remotePath
        self.localPath = localPath
    }
}
