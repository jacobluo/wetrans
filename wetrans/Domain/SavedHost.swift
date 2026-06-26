import Foundation

public enum HostSource: String, Codable, Equatable {
    case manual
    case sshConfigGenerated
}

public enum AuthType: String, Codable, Equatable {
    case password
    case sshKey
}

public struct SavedHost: Identifiable, Codable, Equatable {
    public let id: UUID
    public var source: HostSource
    public var displayName: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authType: AuthType
    public var identityFile: String?
    public var isFavorite: Bool
    public var lastConnectedAt: Date?
    public var lastRemotePath: String?
    public var lastLocalPath: String?
    public var defaultRemotePath: String?
    public var favoriteRemotePaths: [String]
    public var originSSHConfigAlias: String?
    public var resolvedAt: Date?
    public var note: String?

    public init(
        id: UUID = UUID(),
        source: HostSource,
        displayName: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authType: AuthType,
        identityFile: String? = nil,
        isFavorite: Bool = false,
        lastConnectedAt: Date? = nil,
        lastRemotePath: String? = nil,
        lastLocalPath: String? = nil,
        defaultRemotePath: String? = nil,
        favoriteRemotePaths: [String] = [],
        originSSHConfigAlias: String? = nil,
        resolvedAt: Date? = nil,
        note: String? = nil
    ) {
        self.id = id
        self.source = source
        self.displayName = displayName
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authType = authType
        self.identityFile = identityFile
        self.isFavorite = isFavorite
        self.lastConnectedAt = lastConnectedAt
        self.lastRemotePath = lastRemotePath
        self.lastLocalPath = lastLocalPath
        self.defaultRemotePath = defaultRemotePath
        self.favoriteRemotePaths = favoriteRemotePaths
        self.originSSHConfigAlias = originSSHConfigAlias
        self.resolvedAt = resolvedAt
        self.note = note
    }
}

