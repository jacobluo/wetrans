import Foundation

public protocol HostSessionCleaning: Sendable {
    func disconnect(hostId: UUID) async
}

public struct NoopHostSessionCleaner: HostSessionCleaning {
    public init() {}

    public func disconnect(hostId: UUID) async {}
}

@MainActor
public final class SavedHostMaintenance {
    private let catalog: HostCatalog
    private let credentialStore: CredentialStore
    private let trustedHostStore: TrustedHostStore
    private let hostSessionCleaner: HostSessionCleaning

    public init(
        catalog: HostCatalog,
        credentialStore: CredentialStore,
        trustedHostStore: TrustedHostStore,
        hostSessionCleaner: HostSessionCleaning = NoopHostSessionCleaner()
    ) {
        self.catalog = catalog
        self.credentialStore = credentialStore
        self.trustedHostStore = trustedHostStore
        self.hostSessionCleaner = hostSessionCleaner
    }

    public func delete(_ host: SavedHost) async throws {
        try catalog.delete(hostId: host.id)
        try credentialStore.deleteCredentials(hostId: host.id)
        try trustedHostStore.deleteKeys(hostId: host.id)
        await hostSessionCleaner.disconnect(hostId: host.id)
    }

    public func saveEdited(original: SavedHost, edited: SavedHost) async throws {
        try catalog.save(edited)
        if original.authType != edited.authType {
            try credentialStore.deleteCredentials(hostId: edited.id)
        }
    }
}
