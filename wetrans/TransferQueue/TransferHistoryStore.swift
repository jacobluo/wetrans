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
