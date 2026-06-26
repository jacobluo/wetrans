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

    func testUploadSelectionEnqueuesSelectedLocalFilesToCurrentRemotePath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let localDirectory = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [localFile, localDirectory]]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectLocalItem(localFile)
        viewModel.selectLocalItem(localDirectory)
        await viewModel.enqueueUploadSelection()

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].hostId, host.id)
        XCTAssertEqual(tasks[0].hostDisplayName, "dev")
        XCTAssertEqual(tasks[0].direction, .upload)
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/config.yaml")
        XCTAssertEqual(tasks[0].remotePath, "/project/config.yaml")
        XCTAssertEqual(tasks[0].fileName, "config.yaml")
        XCTAssertEqual(tasks[0].totalBytes, 12)
    }

    func testDownloadSelectionEnqueuesSelectedRemoteFilesToCurrentLocalPath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let remoteFile = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": []]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [remoteFile]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectRemoteItem(remoteFile)
        await viewModel.enqueueDownloadSelection()

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].direction, .download)
        XCTAssertEqual(tasks[0].remotePath, "/var/log/app.log")
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/app.log")
        XCTAssertEqual(tasks[0].fileName, "app.log")
        XCTAssertEqual(tasks[0].totalBytes, 42)
    }

    func testContextUploadEnqueuesOnlyClickedLocalFile() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let clicked = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let other = FileItem(name: "other.yaml", path: "/Users/me/Downloads/other.yaml", isDirectory: false, size: 20)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [clicked, other]]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectLocalItem(other)
        await viewModel.enqueueUpload(clicked)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/config.yaml")
        XCTAssertEqual(tasks[0].remotePath, "/project/config.yaml")
        XCTAssertEqual(tasks[0].totalBytes, 12)
    }

    func testContextDownloadEnqueuesOnlyClickedRemoteFile() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let clicked = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [clicked]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()
        await viewModel.enqueueDownload(clicked)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].remotePath, "/var/log/app.log")
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/app.log")
        XCTAssertEqual(tasks[0].totalBytes, 42)
    }

    func testContextUploadRejectsDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let directory = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(hosts: [host], transferQueue: transferQueue)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.enqueueUpload(directory)

        XCTAssertTrue(viewModel.localPanel.errorMessage.contains("Select a file to upload"))
        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks, [])
    }

    func testContextDownloadRejectsDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let directory = FileItem(name: "logs", path: "/var/log/logs", isDirectory: true)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(hosts: [host], transferQueue: transferQueue)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.enqueueDownload(directory)

        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Select a file to download"))
        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks, [])
    }

    func testSuccessfulUploadRefreshesVisibleRemoteDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": []])
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [localFile]]),
            remoteFileSystem: remoteFileSystem,
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectLocalItem(localFile)
        await viewModel.enqueueUploadSelection()

        try await waitUntil {
            remoteFileSystem.listCalls.map(\.path).filter { $0 == "/project" }.count >= 2
        }
    }

    func testSuccessfulDownloadRefreshesVisibleLocalDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let remoteFile = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
        let localFileSystem = FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": []])
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: localFileSystem,
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [remoteFile]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectRemoteItem(remoteFile)
        await viewModel.enqueueDownloadSelection()

        try await waitUntil {
            localFileSystem.listCalls.filter { $0 == "/Users/me/Downloads" }.count >= 2
        }
    }

    func testTransferForDifferentVisibleDirectoryDoesNotRefreshPanels() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": []])
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: remoteFileSystem,
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()
        await transferQueue.enqueue([
            TransferTask(
                hostId: host.id,
                hostDisplayName: host.displayName,
                direction: .upload,
                localPath: "/Users/me/config.yaml",
                remotePath: "/other/config.yaml",
                fileName: "config.yaml",
                totalBytes: 12
            )
        ])
        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project"])
    }

    func testUploadWithoutSelectedHostShowsError() async throws {
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(hosts: [], transferQueue: transferQueue)

        await viewModel.enqueueUploadSelection()

        XCTAssertTrue(viewModel.localPanel.errorMessage.contains("Select a host"))
        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks, [])
    }

    func testRevealLocalItemUsesInjectedFileRevealer() {
        let revealer = RecordingFileRevealer()
        let viewModel = makeViewModel(fileRevealer: revealer)
        let item = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false)

        viewModel.revealLocalItemInFinder(item)

        XCTAssertEqual(revealer.revealedPaths, ["/Users/me/Downloads/config.yaml"])
    }

    func testCopyRemotePathUsesInjectedPasteboardWriter() {
        let pasteboard = RecordingPasteboardWriter()
        let viewModel = makeViewModel(pasteboardWriter: pasteboard)
        let item = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false)

        viewModel.copyRemotePath(item)

        XCTAssertEqual(pasteboard.strings, ["/var/log/app.log"])
    }

    private func makeViewModel(
        hosts: [SavedHost] = [],
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem(),
        transferQueue: TransferQueue = TransferQueue(engine: RecordingTransferEngine()),
        fileRevealer: FileRevealer = RecordingFileRevealer(),
        pasteboardWriter: PasteboardWriting = RecordingPasteboardWriter()
    ) -> MainBrowserViewModel {
        makeViewModel(
            hostCatalog: FakeHostCatalog(hosts: hosts),
            localFileSystem: localFileSystem,
            remoteFileSystem: remoteFileSystem,
            transferQueue: transferQueue,
            fileRevealer: fileRevealer,
            pasteboardWriter: pasteboardWriter
        )
    }

    private func makeViewModel(
        hostCatalog: HostCatalog,
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem(),
        transferQueue: TransferQueue = TransferQueue(engine: RecordingTransferEngine()),
        fileRevealer: FileRevealer = RecordingFileRevealer(),
        pasteboardWriter: PasteboardWriting = RecordingPasteboardWriter()
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
            transferQueue: transferQueue,
            fileRevealer: fileRevealer,
            pasteboardWriter: pasteboardWriter,
            defaultLocalPath: { "/Users/me/Downloads" }
        )
    }
}

private struct RecordingTransferEngine: TransferEngine {
    func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {}
}

private final class RecordingFileRevealer: FileRevealer, @unchecked Sendable {
    private(set) var revealedPaths: [String] = []

    func reveal(path: String) {
        revealedPaths.append(path)
    }
}

private final class RecordingPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    private(set) var strings: [String] = []

    func writeString(_ value: String) {
        strings.append(value)
    }
}

@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition")
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
