import XCTest
@testable import wetrans

@MainActor
final class MainBrowserViewModelTests: XCTestCase {
    func testSingleClickLocalSelectionReplacesPreviousSelection() {
        let first = FileItem(name: "a.txt", path: "/Users/me/Downloads/a.txt", isDirectory: false)
        let second = FileItem(name: "b.txt", path: "/Users/me/Downloads/b.txt", isDirectory: false)
        let viewModel = makeViewModel()

        viewModel.selectLocalItem(first)
        viewModel.selectLocalItem(second)

        XCTAssertEqual(viewModel.localPanel.selectedItemIds, [second.id])
    }

    func testShiftLocalSelectionExtendsAndTogglesSelection() {
        let first = FileItem(name: "a.txt", path: "/Users/me/Downloads/a.txt", isDirectory: false)
        let second = FileItem(name: "b.txt", path: "/Users/me/Downloads/b.txt", isDirectory: false)
        let viewModel = makeViewModel()

        viewModel.selectLocalItem(first)
        viewModel.selectLocalItem(second, intent: .extend)
        viewModel.selectLocalItem(first, intent: .extend)

        XCTAssertEqual(viewModel.localPanel.selectedItemIds, [second.id])
    }

    func testSingleClickRemoteSelectionReplacesPreviousSelection() {
        let first = FileItem(name: "a.log", path: "/var/log/a.log", isDirectory: false)
        let second = FileItem(name: "b.log", path: "/var/log/b.log", isDirectory: false)
        let viewModel = makeViewModel()

        viewModel.selectRemoteItem(first)
        viewModel.selectRemoteItem(second)

        XCTAssertEqual(viewModel.remotePanel.selectedItemIds, [second.id])
    }

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

    func testRefreshLocalListsCurrentLocalPath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localItems = [
            FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        ]
        let localFileSystem = FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": localItems])
        let viewModel = makeViewModel(hosts: [host], localFileSystem: localFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()

        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded(localItems)
        }
        XCTAssertEqual(viewModel.localPanel.loadingState, .loaded(localItems))
        XCTAssertEqual(localFileSystem.listCalls, ["/Users/me/Downloads"])
    }

    func testRefreshLocalReturnsBeforeSlowFileSystemListingCompletes() async throws {
        let localItems = [
            FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false)
        ]
        let localFileSystem = SlowLocalFileSystem(items: localItems, delay: 0.2)
        let viewModel = makeViewModel(localFileSystem: localFileSystem)

        let startedAt = Date()
        viewModel.refreshLocal()
        let elapsed = Date().timeIntervalSince(startedAt)

        XCTAssertLessThan(elapsed, 0.05)
        XCTAssertEqual(viewModel.localPanel.loadingState, .loading)
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded(localItems)
        }
        XCTAssertEqual(localFileSystem.listCalls, ["/Users/me/Downloads"])
    }

    func testOpenLocalDirectoryUpdatesPathAndRefreshes() async throws {
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

        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded(nestedItems)
        }
        XCTAssertEqual(viewModel.localPanel.path, "/Users/me/Downloads/folder")
        XCTAssertEqual(viewModel.localPanel.loadingState, .loaded(nestedItems))
        XCTAssertEqual(catalog.updatePathCalls.last?.local, "/Users/me/Downloads/folder")
    }

    func testEnterLocalPathUpdatesPathAndRefreshes() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let targetItems = [
            FileItem(name: "manual.txt", path: "/Users/me/manual/manual.txt", isDirectory: false)
        ]
        let catalog = FakeHostCatalog(hosts: [host])
        let localFileSystem = FakeLocalFileSystem(listingsByPath: [
            "/Users/me/manual": targetItems
        ])
        let viewModel = makeViewModel(hostCatalog: catalog, localFileSystem: localFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.enterLocalPath("/Users/me/manual")

        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded(targetItems)
        }
        XCTAssertEqual(viewModel.localPanel.path, "/Users/me/manual")
        XCTAssertEqual(localFileSystem.listCalls, ["/Users/me/manual"])
        XCTAssertEqual(catalog.updatePathCalls.last?.local, "/Users/me/manual")
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

    func testEnterRemotePathUpdatesPathAndRefreshes() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteItems = [
            FileItem(name: "release.tar.gz", path: "/srv/releases/release.tar.gz", isDirectory: false)
        ]
        let catalog = FakeHostCatalog(hosts: [host])
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: [
            "/srv/releases": remoteItems
        ])
        let viewModel = makeViewModel(hostCatalog: catalog, remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.enterRemotePath("/srv/releases")

        XCTAssertEqual(viewModel.remotePanel.path, "/srv/releases")
        XCTAssertEqual(viewModel.remotePanel.loadingState, .loaded(remoteItems))
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/srv/releases"])
        XCTAssertEqual(catalog.updatePathCalls.last?.remote, "/srv/releases")
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
        XCTAssertEqual(viewModel.pendingHostKeyTrust, candidate)
        XCTAssertTrue(viewModel.pendingHostKeyTrustMessage.contains(candidate.fingerprintSHA256))
    }

    func testTrustPendingHostKeySavesTrustAndRetriesRemoteListing() async throws {
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
        let remoteItems = [
            FileItem(name: "app.log", path: "/project/app.log", isDirectory: false)
        ]
        let remoteFileSystem = MockRemoteFileSystem(
            listingsByPath: ["/project": remoteItems],
            listErrorsByPath: ["/project": RemoteFileSystemError.hostKeyRequiresTrust(candidate)]
        )
        let trustedHostStore = FakeTrustedHostStore()
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: remoteFileSystem,
            trustedHostStore: trustedHostStore
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        remoteFileSystem.listErrorsByPath = [:]
        await viewModel.trustPendingHostKeyAndRefresh()

        XCTAssertEqual(trustedHostStore.trustedKeys, [candidate])
        XCTAssertNil(viewModel.pendingHostKeyTrust)
        XCTAssertEqual(viewModel.remotePanel.loadingState, .loaded(remoteItems))
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project", "/project"])
    }

    func testRemoteLibSSH2RuntimeErrorShowsActionableMessage() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem()
        remoteFileSystem.connectError = LibSSH2Error.libraryNotFound(["/missing/libssh2.dylib"])
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("libssh2"))
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("brew install libssh2"))
        XCTAssertFalse(viewModel.remotePanel.errorMessage.contains("error 0"))
    }

    func testRemoteStartupOutputConnectionFailureShowsSpecificDiagnostic() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem(
            listErrorsByPath: [
                "/project": RemoteFileSystemError.connectionFailed("Received message too long 1298753394")
            ]
        )
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("remote shell printed text"))
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Detected output prefix: \"Migr\""))
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("~/.bashrc"))
        XCTAssertFalse(viewModel.remotePanel.errorMessage.contains("Received message too long 1298753394"))
    }

    func testRemoteSFTPSubsystemTimeoutShowsSuspectedStartupOutputDiagnostic() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem(
            listErrorsByPath: [
                "/project": RemoteFileSystemError.connectionFailed("Timeout waiting for response from SFTP subsystem")
            ]
        )
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("SFTP did not respond during startup"))
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("ssh <host> true"))
        XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Timeout waiting for response from SFTP subsystem"))
    }

    func testRemoteFXPOpenFailureMessageIsUnchanged() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem(
            listErrorsByPath: [
                "/project": RemoteFileSystemError.connectionFailed("Unable to send FXP_OPEN*")
            ]
        )
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertEqual(viewModel.remotePanel.errorMessage, "Unable to send FXP_OPEN*")
    }

    func testUnrelatedRemoteConnectionFailureMessageIsUnchanged() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let remoteFileSystem = MockRemoteFileSystem(
            listErrorsByPath: [
                "/project": RemoteFileSystemError.connectionFailed("Unable to open SFTP session")
            ]
        )
        let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertEqual(viewModel.remotePanel.errorMessage, "Unable to open SFTP session")
    }

    func testUploadSelectionEnqueuesSelectedLocalFilesToCurrentRemotePath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let localDirectory = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        let nestedFile = FileItem(name: "nested.txt", path: "/Users/me/Downloads/folder/nested.txt", isDirectory: false, size: 7)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(
                listingsByPath: [
                    "/Users/me/Downloads": [localFile, localDirectory],
                    "/Users/me/Downloads/folder": [nestedFile]
                ]
            ),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([localFile, localDirectory])
        }
        viewModel.selectLocalItem(localFile)
        viewModel.selectLocalItem(localDirectory, intent: .extend)
        await viewModel.enqueueUploadSelection()

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 2)
        XCTAssertEqual(tasks[0].hostId, host.id)
        XCTAssertEqual(tasks[0].hostDisplayName, "dev")
        XCTAssertEqual(tasks[0].direction, .upload)
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/config.yaml")
        XCTAssertEqual(tasks[0].remotePath, "/project/config.yaml")
        XCTAssertEqual(tasks[0].fileName, "config.yaml")
        XCTAssertEqual(tasks[0].totalBytes, 12)
        XCTAssertEqual(tasks[1].localPath, "/Users/me/Downloads/folder/nested.txt")
        XCTAssertEqual(tasks[1].remotePath, "/project/folder/nested.txt")
        XCTAssertEqual(tasks[1].fileName, "nested.txt")
        XCTAssertEqual(tasks[1].totalBytes, 7)
    }

    func testUploadSelectionEnqueuesAllSelectedLocalFiles() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let firstFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let secondFile = FileItem(name: "notes.txt", path: "/Users/me/Downloads/notes.txt", isDirectory: false, size: 34)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [firstFile, secondFile]]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([firstFile, secondFile])
        }
        viewModel.selectLocalItem(firstFile)
        viewModel.selectLocalItem(secondFile, intent: .extend)
        await viewModel.enqueueUploadSelection()

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.map(\.localPath), [
            "/Users/me/Downloads/config.yaml",
            "/Users/me/Downloads/notes.txt"
        ])
        XCTAssertEqual(tasks.map(\.remotePath), [
            "/project/config.yaml",
            "/project/notes.txt"
        ])
        XCTAssertEqual(tasks.map(\.totalBytes), [12, 34])
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
        try await waitUntil {
            viewModel.localPanel.loadingState == .empty
        }
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
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([clicked, other])
        }
        viewModel.selectLocalItem(other)
        await viewModel.enqueueUpload(clicked)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.count, 1)
        XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/config.yaml")
        XCTAssertEqual(tasks[0].remotePath, "/project/config.yaml")
        XCTAssertEqual(tasks[0].totalBytes, 12)
    }

    func testContextUploadUsesAllSelectedLocalFilesWhenClickedFileIsSelected() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let firstFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
        let secondFile = FileItem(name: "notes.txt", path: "/Users/me/Downloads/notes.txt", isDirectory: false, size: 34)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [firstFile, secondFile]]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([firstFile, secondFile])
        }
        viewModel.selectLocalItem(firstFile)
        viewModel.selectLocalItem(secondFile, intent: .extend)
        await viewModel.enqueueUpload(secondFile)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.map(\.localPath), [
            "/Users/me/Downloads/config.yaml",
            "/Users/me/Downloads/notes.txt"
        ])
        XCTAssertEqual(tasks.map(\.remotePath), [
            "/project/config.yaml",
            "/project/notes.txt"
        ])
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

    func testContextDownloadUsesAllSelectedRemoteFilesWhenClickedFileIsSelected() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let firstFile = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
        let secondFile = FileItem(name: "error.log", path: "/var/log/error.log", isDirectory: false, size: 56)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": []]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [firstFile, secondFile]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        await viewModel.refreshRemote()
        viewModel.selectRemoteItem(firstFile)
        viewModel.selectRemoteItem(secondFile, intent: .extend)
        await viewModel.enqueueDownload(secondFile)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.map(\.remotePath), [
            "/var/log/app.log",
            "/var/log/error.log"
        ])
        XCTAssertEqual(tasks.map(\.localPath), [
            "/Users/me/Downloads/app.log",
            "/Users/me/Downloads/error.log"
        ])
    }

    func testContextUploadEnqueuesClickedDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let directory = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
        let nestedFile = FileItem(name: "nested.txt", path: "/Users/me/Downloads/folder/nested.txt", isDirectory: false, size: 7)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads/folder": [nestedFile]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.enqueueUpload(directory)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.map(\.localPath), ["/Users/me/Downloads/folder/nested.txt"])
        XCTAssertEqual(tasks.map(\.remotePath), ["/project/folder/nested.txt"])
    }

    func testContextDownloadEnqueuesClickedDirectory() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let directory = FileItem(name: "logs", path: "/var/log/logs", isDirectory: true)
        let nestedFile = FileItem(name: "app.log", path: "/var/log/logs/app.log", isDirectory: false, size: 42)
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log/logs": [nestedFile]]),
            transferQueue: transferQueue
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.enqueueDownload(directory)

        let tasks = await transferQueue.snapshot()
        XCTAssertEqual(tasks.map(\.remotePath), ["/var/log/logs/app.log"])
        XCTAssertEqual(tasks.map(\.localPath), ["/Users/me/Downloads/logs/app.log"])
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
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([localFile])
        }
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

    func testCopyRemoteDebugDetailWritesRedactedFailureToPasteboard() async throws {
        let host = SavedHost.fixture(displayName: "Prod", lastRemotePath: "/Users/alice/project")
        let pasteboard = RecordingPasteboardWriter()
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: MockRemoteFileSystem(
                listErrorsByPath: [
                    "/Users/alice/project": RemoteFileSystemError.permissionDenied("/Users/alice/project")
                ]
            ),
            pasteboardWriter: pasteboard
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()
        viewModel.copyRemoteDebugDetail()

        let copied = try XCTUnwrap(pasteboard.strings.last)
        XCTAssertTrue(copied.contains("panel: Remote"))
        XCTAssertTrue(copied.contains("host: Prod"))
        XCTAssertTrue(copied.contains("/Users/<user>/project"))
        XCTAssertFalse(copied.contains("alice"))
    }

    func testRemoteRefreshFailureLogsDiagnosticEvent() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let logger = RecordingDiagnosticLogger()
        let viewModel = makeViewModel(
            hosts: [host],
            remoteFileSystem: MockRemoteFileSystem(
                listErrorsByPath: ["/project": RemoteFileSystemError.permissionDenied("/project")]
            ),
            logger: logger
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        await viewModel.refreshRemote()

        XCTAssertTrue(logger.entries.contains { $0.event == .remoteRefreshFailed })
    }

    func testUploadingSelectionLogsEnqueuedTransferCount() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let localFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false)
        let logger = RecordingDiagnosticLogger()
        let transferQueue = TransferQueue(engine: RecordingTransferEngine())
        let viewModel = makeViewModel(
            hosts: [host],
            localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [localFile]]),
            remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
            transferQueue: transferQueue,
            logger: logger
        )

        try viewModel.loadHosts()
        viewModel.select(hostId: host.id)
        viewModel.refreshLocal()
        try await waitUntil {
            viewModel.localPanel.loadingState == .loaded([localFile])
        }
        viewModel.selectLocalItem(localFile)
        await viewModel.enqueueUploadSelection()

        XCTAssertTrue(logger.entries.contains { entry in
            entry.event == .transferTasksEnqueued && entry.metadata["count"] == "1"
        })
    }

    private func makeViewModel(
        hosts: [SavedHost] = [],
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem(),
        trustedHostStore: TrustedHostStore = FakeTrustedHostStore(),
        transferQueue: TransferQueue = TransferQueue(engine: RecordingTransferEngine()),
        fileRevealer: FileRevealer = RecordingFileRevealer(),
        pasteboardWriter: PasteboardWriting = RecordingPasteboardWriter(),
        logger: DiagnosticLogging = RecordingDiagnosticLogger()
    ) -> MainBrowserViewModel {
        makeViewModel(
            hostCatalog: FakeHostCatalog(hosts: hosts),
            localFileSystem: localFileSystem,
            remoteFileSystem: remoteFileSystem,
            trustedHostStore: trustedHostStore,
            transferQueue: transferQueue,
            fileRevealer: fileRevealer,
            pasteboardWriter: pasteboardWriter,
            logger: logger
        )
    }

    private func makeViewModel(
        hostCatalog: HostCatalog,
        localFileSystem: LocalFileSystem = FakeLocalFileSystem(),
        remoteFileSystem: MockRemoteFileSystem = MockRemoteFileSystem(),
        trustedHostStore: TrustedHostStore = FakeTrustedHostStore(),
        transferQueue: TransferQueue = TransferQueue(engine: RecordingTransferEngine()),
        fileRevealer: FileRevealer = RecordingFileRevealer(),
        pasteboardWriter: PasteboardWriting = RecordingPasteboardWriter(),
        logger: DiagnosticLogging = RecordingDiagnosticLogger()
    ) -> MainBrowserViewModel {
        let sessionManager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )
        return MainBrowserViewModel(
            hostCatalog: hostCatalog,
            hostSessionManager: sessionManager,
            trustedHostStore: trustedHostStore,
            localFileSystem: localFileSystem,
            transferQueue: transferQueue,
            fileRevealer: fileRevealer,
            pasteboardWriter: pasteboardWriter,
            logger: logger,
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

private final class FakeLocalFileSystem: LocalFileSystem, @unchecked Sendable {
    var listingsByPath: [String: [FileItem]]
    var errorsByPath: [String: Error]
    private let lock = NSLock()
    private var lockedListCalls: [String] = []

    var listCalls: [String] {
        lock.withLock {
            lockedListCalls
        }
    }

    init(listingsByPath: [String: [FileItem]] = [:], errorsByPath: [String: Error] = [:]) {
        self.listingsByPath = listingsByPath
        self.errorsByPath = errorsByPath
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        lock.withLock {
            lockedListCalls.append(path)
        }
        if let error = errorsByPath[path] {
            throw error
        }
        return listingsByPath[path] ?? []
    }
}

private final class SlowLocalFileSystem: LocalFileSystem, @unchecked Sendable {
    private let items: [FileItem]
    private let delay: TimeInterval
    private let lock = NSLock()
    private var lockedListCalls: [String] = []

    var listCalls: [String] {
        lock.withLock {
            lockedListCalls
        }
    }

    init(items: [FileItem], delay: TimeInterval) {
        self.items = items
        self.delay = delay
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        lock.withLock {
            lockedListCalls.append(path)
        }
        Thread.sleep(forTimeInterval: delay)
        return items
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

private final class FakeTrustedHostStore: TrustedHostStore {
    private(set) var trustedKeys: [TrustedHostKey] = []

    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey? {
        trustedKeys.first {
            $0.hostId == hostId && $0.hostname == hostname && $0.port == port
        }
    }

    func trust(_ key: TrustedHostKey) throws {
        trustedKeys.append(key)
    }

    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws {}

    func deleteKeys(hostId: UUID) throws {
        trustedKeys.removeAll { $0.hostId == hostId }
    }
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
