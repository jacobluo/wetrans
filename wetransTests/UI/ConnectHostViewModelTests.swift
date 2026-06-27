import XCTest
@testable import wetrans

@MainActor
final class ConnectHostViewModelTests: XCTestCase {
    func testAppStateTracksConnectHostPresentationAndSelection() {
        let appState = AppState()
        let hostId = UUID()

        appState.showConnectHost()
        appState.selectHost(hostId)
        appState.setTransferQueueExpanded(false)
        appState.showError("Could not load hosts.")
        appState.dismissConnectHost()

        XCTAssertFalse(appState.isShowingConnectHost)
        XCTAssertEqual(appState.selectedHostId, hostId)
        XCTAssertFalse(appState.isTransferQueueExpanded)
        XCTAssertEqual(appState.appErrorMessage, "Could not load hosts.")

        appState.clearError()
        XCTAssertNil(appState.appErrorMessage)
    }

    func testConnectHostEntryAreaUsesCompactCardHeight() {
        XCTAssertLessThanOrEqual(ConnectHostLayout.optionCardHeight, 124)
        XCTAssertLessThanOrEqual(ConnectHostLayout.headerSpacing, 10)
    }

    func testSavedHostEditorActionsUseStandardButtonSize() {
        XCTAssertGreaterThanOrEqual(ConnectHostLayout.savedHostActionButtonMinWidth, 70)
        XCTAssertEqual(ConnectHostLayout.savedHostActionButtonMinHeight, 26)
    }

    func testSavedHostsManagementStateSelectsFirstHostAndFiltersByHostMetadata() {
        let dev = SavedHost(
            source: .sshConfigGenerated,
            displayName: "dev",
            hostname: "192.0.2.10",
            username: "ubuntu",
            authType: .sshKey,
            identityFile: "~/.ssh/id_ed25519",
            originSSHConfigAlias: "dev"
        )
        let prod = SavedHost(
            source: .manual,
            displayName: "prod",
            hostname: "prod.example.com",
            username: "deploy",
            authType: .password
        )
        var state = SavedHostsManagementState(hosts: [dev, prod])

        state.ensureValidSelection()

        XCTAssertEqual(state.selectedHost?.displayName, "dev")
        state.searchText = "deploy"
        XCTAssertEqual(state.filteredHosts.map(\.displayName), ["prod"])
    }

    func testSavedHostsManagementStateDescribesSavedHostWithoutSecrets() {
        let host = SavedHost(
            source: .sshConfigGenerated,
            displayName: "dev",
            hostname: "192.0.2.10",
            username: "ubuntu",
            authType: .sshKey,
            identityFile: "~/.ssh/id_ed25519",
            isFavorite: true,
            lastRemotePath: "/home/ubuntu/project",
            defaultRemotePath: "/home/ubuntu",
            originSSHConfigAlias: "dev",
            note: "Development server"
        )
        let state = SavedHostsManagementState(hosts: [host])

        let detail = state.detailRows(for: host)

        XCTAssertTrue(detail.contains(.init(label: "Source", value: "SSH Config alias dev -> saved host")))
        XCTAssertFalse(detail.map(\.value).contains("secret"))
    }

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

    func testDeletingSavedHostRemovesMetadataCredentialsTrustedKeysAndRuntimeSession() async throws {
        let host = SavedHost.fixture()
        let catalog = InMemoryHostCatalog(hosts: [host])
        let credentials = InMemoryCredentialStore()
        let trustedHosts = InMemoryTrustedHostStore()
        let sessions = RecordingHostSessionCleaner()
        let maintenance = SavedHostMaintenance(
            catalog: catalog,
            credentialStore: credentials,
            trustedHostStore: trustedHosts,
            hostSessionCleaner: sessions
        )

        try await maintenance.delete(host)

        XCTAssertTrue(catalog.hosts.isEmpty)
        XCTAssertEqual(credentials.deletedHostIds, [host.id])
        XCTAssertEqual(trustedHosts.deletedHostIds, [host.id])
        let deletedSessionHostIds = await sessions.snapshot()
        XCTAssertEqual(deletedSessionHostIds, [host.id])
    }

    func testSavingEditedHostDeletesOldCredentialsWhenAuthTypeChanges() async throws {
        let host = SavedHost.fixture(authType: .password)
        let edited = SavedHost.fixture(id: host.id, authType: .sshKey, identityFile: "~/.ssh/id_ed25519")
        let catalog = InMemoryHostCatalog(hosts: [host])
        let credentials = InMemoryCredentialStore()
        let maintenance = SavedHostMaintenance(
            catalog: catalog,
            credentialStore: credentials,
            trustedHostStore: InMemoryTrustedHostStore()
        )

        try await maintenance.saveEdited(original: host, edited: edited)

        XCTAssertEqual(catalog.hosts.first?.authType, .sshKey)
        XCTAssertEqual(credentials.deletedHostIds, [host.id])
    }
}

private extension SavedHost {
    static func fixture(
        id: UUID = UUID(),
        authType: AuthType = .password,
        identityFile: String? = nil
    ) -> SavedHost {
        SavedHost(
            id: id,
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            username: "ubuntu",
            authType: authType,
            identityFile: identityFile
        )
    }
}

private final class InMemoryHostCatalog: HostCatalog {
    var hosts: [SavedHost] = []

    init(hosts: [SavedHost] = []) {
        self.hosts = hosts
    }

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

private final class InMemoryTrustedHostStore: TrustedHostStore {
    var deletedHostIds: [UUID] = []

    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey? { nil }
    func trust(_ key: TrustedHostKey) throws {}
    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws {}

    func deleteKeys(hostId: UUID) throws {
        deletedHostIds.append(hostId)
    }
}

private actor RecordingHostSessionCleaner: HostSessionCleaning {
    private(set) var deletedHostIds: [UUID] = []

    func disconnect(hostId: UUID) async {
        deletedHostIds.append(hostId)
    }

    func snapshot() -> [UUID] {
        deletedHostIds
    }
}
