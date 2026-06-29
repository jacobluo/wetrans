import Foundation

public protocol TransferHistoryStore: Sendable {
    func load() throws -> [TransferTask]
    func save(_ tasks: [TransferTask]) throws
}

public final class FileTransferHistoryStore: TransferHistoryStore, @unchecked Sendable {
    private let store: JSONDocumentStore<TransferHistoryDocument>

    public convenience init(applicationSupportDirectory: URL = FileManager.wetransApplicationSupportDirectory) {
        self.init(url: applicationSupportDirectory.appendingPathComponent("transfer_history.json"))
    }

    public init(url: URL) {
        self.store = JSONDocumentStore<TransferHistoryDocument>(url: url)
    }

    public func load() throws -> [TransferTask] {
        try store.load(default: TransferHistoryDocument()).tasks
    }

    public func save(_ tasks: [TransferTask]) throws {
        try store.save(TransferHistoryDocument(tasks: tasks))
    }
}

public struct EmptyTransferHistoryStore: TransferHistoryStore {
    public init() {}

    public func load() throws -> [TransferTask] {
        []
    }

    public func save(_ tasks: [TransferTask]) throws {}
}

public struct TransferQueueSettings: Equatable, Sendable {
    public let concurrencyLimits: TransferQueueConcurrencyLimits

    public init(concurrencyLimits: TransferQueueConcurrencyLimits = .init(global: 3, perHost: 2)) {
        self.concurrencyLimits = concurrencyLimits
    }
}

public protocol TransferQueueSettingsStore: Sendable {
    func load() throws -> TransferQueueSettings?
    func save(_ settings: TransferQueueSettings) throws
}

public final class FileTransferQueueSettingsStore: TransferQueueSettingsStore, @unchecked Sendable {
    private let store: JSONDocumentStore<TransferQueueSettingsDocument>

    public convenience init(applicationSupportDirectory: URL = FileManager.wetransApplicationSupportDirectory) {
        self.init(url: applicationSupportDirectory.appendingPathComponent("transfer_queue_settings.json"))
    }

    public init(url: URL) {
        self.store = JSONDocumentStore<TransferQueueSettingsDocument>(url: url)
    }

    public func load() throws -> TransferQueueSettings? {
        let document = try store.load(default: TransferQueueSettingsDocument())
        guard document.schemaVersion == 1 else {
            throw JSONDocumentStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return TransferQueueSettings(
            concurrencyLimits: TransferQueueConcurrencyLimits(
                global: document.globalConcurrencyLimit,
                perHost: document.perHostConcurrencyLimit
            )
        )
    }

    public func save(_ settings: TransferQueueSettings) throws {
        try store.save(
            TransferQueueSettingsDocument(
                globalConcurrencyLimit: settings.concurrencyLimits.global,
                perHostConcurrencyLimit: settings.concurrencyLimits.perHost
            )
        )
    }
}

public struct EmptyTransferQueueSettingsStore: TransferQueueSettingsStore {
    public init() {}

    public func load() throws -> TransferQueueSettings? {
        nil
    }

    public func save(_ settings: TransferQueueSettings) throws {}
}
