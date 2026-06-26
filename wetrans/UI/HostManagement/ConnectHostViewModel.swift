import Combine
import Foundation

@MainActor
public final class ConnectHostViewModel: ObservableObject {
    @Published public var draft: HostDraft
    @Published public private(set) var savedHost: SavedHost?
    @Published public private(set) var errorMessage: String?

    private let catalog: HostCatalog
    private let credentialStore: CredentialStore

    public init(
        catalog: HostCatalog,
        credentialStore: CredentialStore,
        draft: HostDraft = HostDraft(
            source: .manual,
            displayName: "",
            hostname: "",
            port: 22,
            username: NSUserName(),
            authType: .password
        )
    ) {
        self.catalog = catalog
        self.credentialStore = credentialStore
        self.draft = draft
    }

    public func saveDraft() async throws {
        let host = try draft.makeSavedHost()
        try catalog.save(host)
        try saveCredentials(for: host.id)

        savedHost = host
        errorMessage = nil
    }

    private func saveCredentials(for hostId: UUID) throws {
        if let password = draft.password?.trimmedNilIfEmpty {
            try credentialStore.savePassword(password, hostId: hostId)
        }
        if let keyPassphrase = draft.keyPassphrase?.trimmedNilIfEmpty {
            try credentialStore.saveKeyPassphrase(keyPassphrase, hostId: hostId)
        }
    }
}

