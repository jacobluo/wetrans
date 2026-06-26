import Foundation

public final class FileTrustedHostStore: TrustedHostStore {
    private let store: JSONDocumentStore<TrustedHostKeysDocument>

    public init(store: JSONDocumentStore<TrustedHostKeysDocument>) {
        self.store = store
    }

    public convenience init(applicationSupportDirectory: URL) {
        self.init(
            store: JSONDocumentStore(
                url: applicationSupportDirectory.appendingPathComponent("known_hosts.json")
            )
        )
    }

    public func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey? {
        try loadDocument().trustedHostKeys.first {
            $0.hostId == hostId && $0.hostname == hostname && $0.port == port
        }
    }

    public func trust(_ key: TrustedHostKey) throws {
        var document = try loadDocument()
        document.trustedHostKeys.removeAll {
            $0.hostId == key.hostId && $0.hostname == key.hostname && $0.port == key.port
        }
        document.trustedHostKeys.append(key)
        try store.save(document)
    }

    public func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws {
        var document = try loadDocument()
        guard let index = document.trustedHostKeys.firstIndex(where: {
            $0.hostId == hostId && $0.hostname == hostname && $0.port == port
        }) else {
            return
        }
        document.trustedHostKeys[index].lastVerifiedAt = date
        try store.save(document)
    }

    public func deleteKeys(hostId: UUID) throws {
        var document = try loadDocument()
        document.trustedHostKeys.removeAll { $0.hostId == hostId }
        try store.save(document)
    }

    private func loadDocument() throws -> TrustedHostKeysDocument {
        let document = try store.load(default: TrustedHostKeysDocument())
        guard document.schemaVersion == 1 else {
            throw JSONDocumentStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }
}

