import XCTest
@testable import wetrans

final class HostSessionManagerTests: XCTestCase {
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

