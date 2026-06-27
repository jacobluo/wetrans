import XCTest
@testable import wetrans

final class HostSessionManagerTests: XCTestCase {
    func testInitialStateUsesHomeDirectoryWhenHostHasNoSavedLocalPath() {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let manager = HostSessionManager(
            remoteFileSystem: MockRemoteFileSystem(),
            credentialStore: InMemoryCredentialStore()
        )

        XCTAssertEqual(manager.state(for: host).currentLocalPath, FileManager.default.homeDirectoryForCurrentUser.path)
    }

    func testFirstRemoteListingConnectsThenListsCurrentPath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = MockRemoteFileSystem(
            listingsByPath: ["/project": [FileItem(name: "app.py", path: "/project/app.py", isDirectory: false)]]
        )
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        let items = try await manager.listRemoteDirectory(for: host)

        XCTAssertEqual(items.map(\.name), ["app.py"])
        XCTAssertEqual(remoteFileSystem.connectCalls.count, 1)
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project"])
    }

    func testSecondListingForSameHostReusesSession() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        _ = try await manager.listRemoteDirectory(for: host)
        _ = try await manager.listRemoteDirectory(for: host)

        XCTAssertEqual(remoteFileSystem.connectCalls.count, 1)
        XCTAssertEqual(remoteFileSystem.listCalls.count, 2)
    }

    func testRemoteListingReconnectsOnceWhenCachedSessionFails() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let initialItems = [
            FileItem(name: "README.md", path: "/project/README.md", isDirectory: false)
        ]
        let recoveredItems = [
            FileItem(name: "app.log", path: "/project/app.log", isDirectory: false)
        ]
        let remoteFileSystem = SequencedListRemoteFileSystem(
            listResults: [
                .success(initialItems),
                .failure(RemoteFileSystemError.connectionFailed("Unable to send FXP_OPEN*")),
                .success(recoveredItems)
            ]
        )
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        let firstItems = try await manager.listRemoteDirectory(for: host)
        let items = try await manager.listRemoteDirectory(for: host)

        let snapshot = await remoteFileSystem.snapshot()
        XCTAssertEqual(firstItems, initialItems)
        XCTAssertEqual(items, recoveredItems)
        XCTAssertEqual(snapshot.connectCount, 2)
        XCTAssertEqual(snapshot.disconnectCount, 1)
        XCTAssertEqual(snapshot.listPaths, ["/project", "/project", "/project"])
        XCTAssertEqual(snapshot.listSessionIds[0], snapshot.listSessionIds[1])
        XCTAssertNotEqual(snapshot.listSessionIds[1], snapshot.listSessionIds[2])
        XCTAssertEqual(Set(snapshot.listSessionIds).count, 2)
        XCTAssertTrue(manager.state(for: host).isConnected)
    }

    func testRemoteListingDoesNotReconnectForPermissionDenied() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = SequencedListRemoteFileSystem(
            listResults: [
                .success([]),
                .failure(RemoteFileSystemError.permissionDenied("/project"))
            ]
        )
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        _ = try await manager.listRemoteDirectory(for: host)

        do {
            _ = try await manager.listRemoteDirectory(for: host)
            XCTFail("Expected permissionDenied")
        } catch RemoteFileSystemError.permissionDenied(let path) {
            XCTAssertEqual(path, "/project")
        }

        let snapshot = await remoteFileSystem.snapshot()
        XCTAssertEqual(snapshot.connectCount, 1)
        XCTAssertEqual(snapshot.disconnectCount, 0)
        XCTAssertEqual(snapshot.listPaths, ["/project", "/project"])
        XCTAssertEqual(Set(snapshot.listSessionIds).count, 1)
    }

    func testConcurrentFirstListingsForSameHostSharePendingSession() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = SlowConnectRemoteFileSystem(listingsByPath: ["/project": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        async let first: [FileItem] = manager.listRemoteDirectory(for: host)
        async let second: [FileItem] = manager.listRemoteDirectory(for: host)
        _ = try await (first, second)

        let counts = await remoteFileSystem.callCounts()
        XCTAssertEqual(counts.connect, 1)
        XCTAssertEqual(counts.list, 2)
    }

    func testUpdatingRemotePathChangesListedPath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/var/log": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        manager.updateRemotePath("/var/log", for: host)
        _ = try await manager.listRemoteDirectory(for: host)

        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/var/log"])
    }

    func testListingSpecificRemotePathDoesNotChangeCurrentPath() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = MockRemoteFileSystem(
            listingsByPath: [
                "/project/logs": [
                    FileItem(name: "app.log", path: "/project/logs/app.log", isDirectory: false)
                ]
            ]
        )
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        let items = try await manager.listRemoteDirectory(path: "/project/logs", for: host)

        XCTAssertEqual(items.map(\.name), ["app.log"])
        XCTAssertEqual(manager.state(for: host).currentRemotePath, "/project")
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project/logs"])
    }

    func testNewHostWithoutRemotePathListsSFTPHomeDirectory() async throws {
        let host = SavedHost.fixture()
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: [".": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        _ = try await manager.listRemoteDirectory(for: host)

        XCTAssertEqual(manager.state(for: host).currentRemotePath, ".")
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["."])
    }

    func testSwitchingHostsPreservesEachHostPath() {
        let dev = SavedHost.fixture(displayName: "dev", lastRemotePath: "/project")
        let prod = SavedHost.fixture(displayName: "prod", lastRemotePath: "/var/www")
        let manager = HostSessionManager(
            remoteFileSystem: MockRemoteFileSystem(),
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        manager.updateRemotePath("/project/src", for: dev)
        manager.updateRemotePath("/var/www/current", for: prod)

        XCTAssertEqual(manager.state(for: dev).currentRemotePath, "/project/src")
        XCTAssertEqual(manager.state(for: prod).currentRemotePath, "/var/www/current")
    }

    func testDisconnectClearsLiveSessionButPreservesPaths() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/project")
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )

        _ = try await manager.listRemoteDirectory(for: host)
        await manager.disconnect(hostId: host.id)

        XCTAssertEqual(remoteFileSystem.disconnectedSessions.count, 1)
        XCTAssertFalse(manager.state(for: host).isConnected)
        XCTAssertEqual(manager.state(for: host).currentRemotePath, "/project")
    }

    func testDisconnectIdleSessionsDisconnectsOnlyExpiredSessionsAndPreservesPaths() async throws {
        let oldHost = SavedHost.fixture(displayName: "old", lastRemotePath: "/old")
        let recentHost = SavedHost.fixture(displayName: "recent", lastRemotePath: "/recent")
        let clock = TestClock(date: Date(timeIntervalSince1970: 1_700_000_000))
        let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/old": [], "/recent": []])
        let manager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" },
            now: { clock.date }
        )

        _ = try await manager.listRemoteDirectory(for: oldHost)
        clock.advance(by: 600)
        _ = try await manager.listRemoteDirectory(for: recentHost)
        clock.advance(by: 600)

        await manager.disconnectIdleSessions(now: clock.date, idleTimeout: 900)

        XCTAssertEqual(remoteFileSystem.disconnectedSessions.map(\.hostId), [oldHost.id])
        XCTAssertFalse(manager.state(for: oldHost).isConnected)
        XCTAssertTrue(manager.state(for: recentHost).isConnected)
        XCTAssertEqual(manager.state(for: oldHost).currentRemotePath, "/old")
        XCTAssertEqual(manager.state(for: recentHost).currentRemotePath, "/recent")
    }
}

private actor SlowConnectRemoteFileSystem: RemoteFileSystem {
    private let listingsByPath: [String: [FileItem]]
    private(set) var connectCallCount = 0
    private(set) var listCallCount = 0

    init(listingsByPath: [String: [FileItem]]) {
        self.listingsByPath = listingsByPath
    }

    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession {
        connectCallCount += 1
        try await Task.sleep(nanoseconds: 50_000_000)
        return RemoteSession(hostId: spec.hostId, displayName: spec.displayName)
    }

    func callCounts() -> (connect: Int, list: Int) {
        (connectCallCount, listCallCount)
    }

    func disconnect(_ session: RemoteSession) async {}

    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem] {
        listCallCount += 1
        return listingsByPath[path] ?? []
    }

    func ensureDirectory(_ path: String, in session: RemoteSession) async throws {}

    func upload(
        _ request: UploadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {}

    func download(
        _ request: DownloadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {}
}

private final class TestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var currentDate: Date

    init(date: Date) {
        self.currentDate = date
    }

    var date: Date {
        lock.withLock { currentDate }
    }

    func advance(by interval: TimeInterval) {
        lock.withLock {
            currentDate = currentDate.addingTimeInterval(interval)
        }
    }
}

private actor SequencedListRemoteFileSystem: RemoteFileSystem {
    struct Snapshot {
        let connectCount: Int
        let disconnectCount: Int
        let listPaths: [String]
        let listSessionIds: [UUID]
    }

    private var listResults: [Result<[FileItem], Error>]
    private var connectCallCount = 0
    private var disconnectedSessions: [RemoteSession] = []
    private var listCalls: [(path: String, session: RemoteSession)] = []

    init(listResults: [Result<[FileItem], Error>]) {
        self.listResults = listResults
    }

    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession {
        connectCallCount += 1
        return RemoteSession(hostId: spec.hostId, displayName: spec.displayName)
    }

    func disconnect(_ session: RemoteSession) async {
        disconnectedSessions.append(session)
    }

    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem] {
        listCalls.append((path: path, session: session))
        guard !listResults.isEmpty else {
            return []
        }
        switch listResults.removeFirst() {
        case .success(let items):
            return items
        case .failure(let error):
            throw error
        }
    }

    func ensureDirectory(_ path: String, in session: RemoteSession) async throws {}

    func snapshot() -> Snapshot {
        Snapshot(
            connectCount: connectCallCount,
            disconnectCount: disconnectedSessions.count,
            listPaths: listCalls.map(\.path),
            listSessionIds: listCalls.map(\.session.id)
        )
    }

    func upload(
        _ request: UploadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {}

    func download(
        _ request: DownloadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {}
}

private extension SavedHost {
    static func fixture(
        id: UUID = UUID(),
        displayName: String = "dev",
        lastRemotePath: String? = nil
    ) -> SavedHost {
        SavedHost(
            id: id,
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            lastRemotePath: lastRemotePath
        )
    }
}
