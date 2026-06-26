import Foundation

public struct HostsDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var hosts: [SavedHost]

    public init(schemaVersion: Int = 1, hosts: [SavedHost] = []) {
        self.schemaVersion = schemaVersion
        self.hosts = hosts
    }
}

public struct TrustedHostKeysDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var trustedHostKeys: [TrustedHostKey]

    public init(schemaVersion: Int = 1, trustedHostKeys: [TrustedHostKey] = []) {
        self.schemaVersion = schemaVersion
        self.trustedHostKeys = trustedHostKeys
    }
}

public struct TransferHistoryDocument: Codable, Equatable {
    public var schemaVersion: Int
    public var tasks: [TransferTask]

    public init(schemaVersion: Int = 1, tasks: [TransferTask] = []) {
        self.schemaVersion = schemaVersion
        self.tasks = tasks
    }
}

