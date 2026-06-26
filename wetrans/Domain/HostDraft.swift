import Foundation

public struct SSHConfigWarning: Codable, Equatable {
    public var key: String
    public var value: String
    public var message: String

    public init(key: String, value: String, message: String) {
        self.key = key
        self.value = value
        self.message = message
    }
}

public struct HostDraft: Equatable {
    public var source: HostSource
    public var displayName: String
    public var hostname: String
    public var port: Int
    public var username: String
    public var authType: AuthType
    public var identityFile: String?
    public var password: String?
    public var keyPassphrase: String?
    public var defaultRemotePath: String?
    public var originSSHConfigAlias: String?
    public var resolvedAt: Date?
    public var unsupportedOptions: [SSHConfigWarning]

    public init(
        source: HostSource,
        displayName: String,
        hostname: String,
        port: Int = 22,
        username: String,
        authType: AuthType,
        identityFile: String? = nil,
        password: String? = nil,
        keyPassphrase: String? = nil,
        defaultRemotePath: String? = nil,
        originSSHConfigAlias: String? = nil,
        resolvedAt: Date? = nil,
        unsupportedOptions: [SSHConfigWarning] = []
    ) {
        self.source = source
        self.displayName = displayName
        self.hostname = hostname
        self.port = port
        self.username = username
        self.authType = authType
        self.identityFile = identityFile
        self.password = password
        self.keyPassphrase = keyPassphrase
        self.defaultRemotePath = defaultRemotePath
        self.originSSHConfigAlias = originSSHConfigAlias
        self.resolvedAt = resolvedAt
        self.unsupportedOptions = unsupportedOptions
    }

    public func makeSavedHost(id: UUID = UUID()) throws -> SavedHost {
        try HostValidator.validate(self)
        return SavedHost(
            id: id,
            source: source,
            displayName: displayName.trimmedForValidation,
            hostname: hostname.trimmedForValidation,
            port: port,
            username: username.trimmedForValidation,
            authType: authType,
            identityFile: identityFile?.trimmedNilIfEmpty,
            defaultRemotePath: defaultRemotePath?.trimmedNilIfEmpty,
            favoriteRemotePaths: [],
            originSSHConfigAlias: originSSHConfigAlias?.trimmedNilIfEmpty,
            resolvedAt: resolvedAt
        )
    }
}

