import Foundation

public struct ResolvedSSHConfig: Equatable {
    public let alias: String
    public let hostname: String
    public let user: String?
    public let port: Int
    public let identityFiles: [String]
    public let proxyJump: String?
    public let proxyCommand: String?

    public init(
        alias: String,
        hostname: String,
        user: String?,
        port: Int,
        identityFiles: [String],
        proxyJump: String?,
        proxyCommand: String?
    ) {
        self.alias = alias
        self.hostname = hostname
        self.user = user
        self.port = port
        self.identityFiles = identityFiles
        self.proxyJump = proxyJump
        self.proxyCommand = proxyCommand
    }
}

