import Foundation

public protocol HostCatalog {
    func load() throws -> [SavedHost]
    func save(_ host: SavedHost) throws
    func delete(hostId: UUID) throws
    func markConnected(hostId: UUID, at date: Date) throws
    func updatePaths(hostId: UUID, local: String?, remote: String?) throws
    func setFavorite(hostId: UUID, isFavorite: Bool) throws
}

public final class FileHostCatalog: HostCatalog {
    private let store: JSONDocumentStore<HostsDocument>

    public init(store: JSONDocumentStore<HostsDocument>) {
        self.store = store
    }

    public convenience init(applicationSupportDirectory: URL) {
        self.init(
            store: JSONDocumentStore(
                url: applicationSupportDirectory.appendingPathComponent("hosts.json")
            )
        )
    }

    public func load() throws -> [SavedHost] {
        try loadDocument().hosts
    }

    public func save(_ host: SavedHost) throws {
        try HostValidator.validate(host)
        var document = try loadDocument()
        document.hosts.removeAll { $0.id == host.id }
        document.hosts.append(host)
        document.hosts.sort { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
        try store.save(document)
    }

    public func delete(hostId: UUID) throws {
        var document = try loadDocument()
        document.hosts.removeAll { $0.id == hostId }
        try store.save(document)
    }

    public func markConnected(hostId: UUID, at date: Date) throws {
        try update(hostId: hostId) { host in
            host.lastConnectedAt = date
        }
    }

    public func updatePaths(hostId: UUID, local: String?, remote: String?) throws {
        try update(hostId: hostId) { host in
            if let local {
                host.lastLocalPath = local
            }
            if let remote {
                host.lastRemotePath = remote
            }
        }
    }

    public func setFavorite(hostId: UUID, isFavorite: Bool) throws {
        try update(hostId: hostId) { host in
            host.isFavorite = isFavorite
        }
    }

    private func update(hostId: UUID, mutate: (inout SavedHost) -> Void) throws {
        var document = try loadDocument()
        guard let index = document.hosts.firstIndex(where: { $0.id == hostId }) else {
            return
        }
        mutate(&document.hosts[index])
        try HostValidator.validate(document.hosts[index])
        try store.save(document)
    }

    private func loadDocument() throws -> HostsDocument {
        let document = try store.load(default: HostsDocument())
        guard document.schemaVersion == 1 else {
            throw JSONDocumentStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }
}

