import XCTest
@testable import wetrans

@MainActor
final class ConnectHostViewModelTests: XCTestCase {
    func testSavingManualDraftSavesHostAndPasswordThroughCredentialStore() async throws {
        let catalog = InMemoryHostCatalog()
        let credentials = InMemoryCredentialStore()
        let viewModel = ConnectHostViewModel(catalog: catalog, credentialStore: credentials)

        viewModel.draft = HostDraft.validManualFixture()
        viewModel.draft.password = "secret"

        try await viewModel.saveDraft()

        let host = try XCTUnwrap(catalog.hosts.first)
        XCTAssertEqual(host.displayName, "dev")
        XCTAssertEqual(credentials.passwords[host.id], "secret")
        XCTAssertNil(host.originSSHConfigAlias)
    }

    func testSavingKeyDraftSavesPassphraseThroughCredentialStore() async throws {
        let catalog = InMemoryHostCatalog()
        let credentials = InMemoryCredentialStore()
        let viewModel = ConnectHostViewModel(catalog: catalog, credentialStore: credentials)

        viewModel.draft = HostDraft(
            source: .manual,
            displayName: "prod",
            hostname: "prod.example.com",
            username: "deploy",
            authType: .sshKey,
            identityFile: "~/.ssh/id_ed25519",
            keyPassphrase: "phrase"
        )

        try await viewModel.saveDraft()

        let host = try XCTUnwrap(catalog.hosts.first)
        XCTAssertEqual(host.authType, .sshKey)
        XCTAssertEqual(credentials.passphrases[host.id], "phrase")
        XCTAssertNil(credentials.passwords[host.id])
    }
}

private final class InMemoryHostCatalog: HostCatalog {
    var hosts: [SavedHost] = []

    func load() throws -> [SavedHost] { hosts }

    func save(_ host: SavedHost) throws {
        hosts.removeAll { $0.id == host.id }
        hosts.append(host)
    }

    func delete(hostId: UUID) throws {
        hosts.removeAll { $0.id == hostId }
    }

    func markConnected(hostId: UUID, at date: Date) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        hosts[index].lastConnectedAt = date
    }

    func updatePaths(hostId: UUID, local: String?, remote: String?) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        if let local { hosts[index].lastLocalPath = local }
        if let remote { hosts[index].lastRemotePath = remote }
    }

    func setFavorite(hostId: UUID, isFavorite: Bool) throws {
        guard let index = hosts.firstIndex(where: { $0.id == hostId }) else { return }
        hosts[index].isFavorite = isFavorite
    }
}

