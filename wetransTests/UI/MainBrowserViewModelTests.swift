import XCTest
@testable import wetrans

@MainActor
final class MainBrowserViewModelTests: XCTestCase {
    func testLoadHostsAndSelectRestoresPanelPaths() throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let viewModel = makeViewModel(hosts: [host])

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)

        XCTAssertEqual(viewModel.sidebarViewModel.groups.myHosts.map(\.id), [host.id])
        XCTAssertEqual(viewModel.selectedHost?.id, host.id)
        XCTAssertEqual(viewModel.localPanel.path, "/Users/me/Downloads")
        XCTAssertEqual(viewModel.remotePanel.path, "/project")
        XCTAssertEqual(viewModel.remotePanel.title, "dev")
    }

    func testRefreshLocalListsCurrentLocalPath() throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localItems = [
            FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        ]
        let localFileSystem = FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": localItems])
        let viewModel = makeViewModel(hosts: [host], localFileSystem: localFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()

        XCTAssertEqual(viewModel.localPanel.loadingState, .loaded(localItems))
        XCTAssertEqual(localFileSystem.listCalls, ["/Users/me/Downloads"])
    }

    func testOpenLocalDirectoryUpdatesPathAndRefreshes() throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let folder = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        let nestedItems = [
            FileItem(name: "nested.txt", path: "/Users/me/Downloads/folder/nested.txt", isDirectory: false)
        ]
        let catalog = FakeHostCatalog(hosts: [host])
        let localFileSystem = FakeLocalFileSystem(listingsByPath: [
            "/Users/me/Downloads": [folder],
            "/Users/me/Downloads/folder": nestedItems
        ])
        let viewModel = makeViewModel(hostCatalog: catalog, localFileSystem: localFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.openLocalItem(folder)

        XCTAssertEqual(viewModel.localPanel.path, "/Users/me/Downloads/folder")
        XCTAssertEqual(viewModel.localPanel.loadingState, .loaded(nestedItems))
        XCTAssertEqual(catalog.updatePathCalls.last?.local, "/Users/me/Downloads/folder")
    }

    func testRefreshRemoteListsCurrentRemotePath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteItems = [
            FileItem(name: "app.log", path: "/project/app.log", isDirectory: false)
        ]
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": remoteItems])
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertEqual(viewModel.remotePanel.loadingState, .loaded(remoteItems))
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project"])
    }

    func testOpenRemoteDirectoryUpdatesPathAndRefreshes() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let folder = FileItem(name: "logs", path: "/project/logs", isDirectory: true)
        let nestedItems = [
            FileItem(name: "app.log", path: "/project/logs/app.log", isDirectory: false)
        ]
        let catalog = FakeHostCatalog(hosts: [host])
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: [
            "/project/logs": nestedItems
        ])
        let viewModel = makeViewModel(hostCatalog: catalog, remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.openRemoteItem(folder)

        XCTAssertEqual(viewModel.remotePanel.path, "/project/logs")
        XCTAssertEqual(viewModel.remotePanel.loadingState, .loaded(nestedItems))
        XCTAssertEqual(catalog.updatePathCalls.last?.remote, "/project/logs")
    }

    func testRemoteErrorPreservesPathAndShowsHostKeyMessage() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let candidate = TrustedHostKey(
            hostId: host.id,
            hostname: host.hostname,
            port: host.port,
            keyType: "ssh-ed25519",
            fingerprintSHA256: "SHA256:candidate",
            firstTrustedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let remoteFileSystem = MockRemoteFileSystem(
            listErrorsByPath: ["/project": RemoteFileSystemError.hostKeyRequiresTrust(candidate)]
        )
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertEqual(viewModel.remotePanel.path, "/project")
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Host key requires confirmation"))
    }

    private func makeViewModel(
        hosts: [SavedHost] = [],
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem()
    ) -> MainBrowserViewModel {
        makeViewModel(
            hostCatalog: FakeHostCatalog(hosts: hosts),
            localFileSystem: localFileSystem,
            remoteFileSystem: remoteFileSystem
        )
    }

    private func makeViewModel(
        hostCatalog: HostCatalog,
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem()
    ) -> MainBrowserViewModel {
        let sessionManager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )
        return MainBrowserViewModel(
            hostCatalog: hostCatalog,
            hostSessionManager: sessionManager,
            localFileSystem: localFileSystem,
            defaultLocalPath: { "/Users/me/Downloads" }
        )
    }
}

private final class FakeLocalFileSystem: LocalFileSystem {
    var listingsByPath: [String: [FileItem]]
    var errorsByPath: [String: Error]
    private(set) var listCalls: [String] = []

    init(listingsByPath: [String: [FileItem]] = [:], errorsByPath: [String: Error] = [:]) {
        self.listingsByPath = listingsByPath
        self.errorsByPath = errorsByPath
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        listCalls.append(path)
        if let error = errorsByPath[path] {
            throw error
        }
        return listingsByPath[path] ?? []
    }
}

private final class FakeHostCatalog: HostCatalog {
    struct UpdatePathCall: Equatable {
        let hostId: UUID
        let local: String?
        let remote: String?
    }

    var hosts: [SavedHost]
    private(set) var updatePathCalls: [UpdatePathCall] = []

    init(hosts: [SavedHost]) {
        self.hosts = hosts
    }

    func load() throws -> [SavedHost] {
        hosts
    }

    func save(_ host: SavedHost) throws {}

    func delete(hostId: UUID) throws {}

    func markConnected(hostId: UUID, at date: Date) throws {}

    func updatePaths(hostId: UUID, local: String?, remote: String?) throws {
        updatePathCalls.append(UpdatePathCall(hostId: hostId, local: local, remote: remote))
    }

    func setFavorite(hostId: UUID, isFavorite: Bool) throws {}
}

private extension SavedHost {
    static func fixture(
        id: UUID = UUID(),
        displayName: String = "dev",
        lastRemotePath: String? = nil,
        lastLocalPath: String? = nil
    ) -> SavedHost {
        SavedHost(
            id: id,
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            lastRemotePath: lastRemotePath,
            lastLocalPath: lastLocalPath
        )
    }
}
