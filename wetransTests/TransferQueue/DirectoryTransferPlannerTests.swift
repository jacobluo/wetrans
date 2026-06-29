import XCTest
@testable import wetrans

final class DirectoryTransferPlannerTests: XCTestCase {
    func testUploadDirectoryExpandsFilesAndPreservesTopLevelDirectoryName() throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let site = FileItem(name: "site", path: "/Users/me/Downloads/site", isDirectory: true)
        let localFileSystem = FakePlannerLocalFileSystem(
            listingsByPath: [
                "/Users/me/Downloads/site": [
                    FileItem(name: "index.html", path: "/Users/me/Downloads/site/index.html", isDirectory: false, size: 12),
                    FileItem(name: "assets", path: "/Users/me/Downloads/site/assets", isDirectory: true)
                ],
                "/Users/me/Downloads/site/assets": [
                    FileItem(name: "app.js", path: "/Users/me/Downloads/site/assets/app.js", isDirectory: false, size: 34)
                ]
            ]
        )
        let planner = DirectoryTransferPlanner(localFileSystem: localFileSystem)

        let tasks = try planner.uploadTasks(for: [site], host: host, remoteDirectory: "/var/www")

        XCTAssertEqual(tasks.map(\.localPath), [
            "/Users/me/Downloads/site/index.html",
            "/Users/me/Downloads/site/assets/app.js"
        ])
        XCTAssertEqual(tasks.map(\.remotePath), [
            "/var/www/site/index.html",
            "/var/www/site/assets/app.js"
        ])
        XCTAssertEqual(tasks.map(\.fileName), ["index.html", "app.js"])
        XCTAssertEqual(tasks.map(\.totalBytes), [12, 34])
        XCTAssertEqual(localFileSystem.listCalls, [
            "/Users/me/Downloads/site",
            "/Users/me/Downloads/site/assets"
        ])
    }

    func testUploadDirectorySkipsSymlinkDirectories() throws {
        let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
        let site = FileItem(name: "site", path: "/Users/me/Downloads/site", isDirectory: true)
        let localFileSystem = FakePlannerLocalFileSystem(
            listingsByPath: [
                "/Users/me/Downloads/site": [
                    FileItem(name: "linked", path: "/Users/me/Downloads/site/linked", isDirectory: true, isSymlink: true),
                    FileItem(name: "index.html", path: "/Users/me/Downloads/site/index.html", isDirectory: false, size: 12)
                ],
                "/Users/me/Downloads/site/linked": [
                    FileItem(name: "secret.txt", path: "/Users/me/Downloads/site/linked/secret.txt", isDirectory: false)
                ]
            ]
        )
        let planner = DirectoryTransferPlanner(localFileSystem: localFileSystem)

        let tasks = try planner.uploadTasks(for: [site], host: host, remoteDirectory: "/var/www")

        XCTAssertEqual(tasks.map(\.remotePath), ["/var/www/site/index.html"])
        XCTAssertEqual(localFileSystem.listCalls, ["/Users/me/Downloads/site"])
    }

    func testDownloadDirectoryExpandsRemoteFilesAndPreservesTopLevelDirectoryName() async throws {
        let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
        let logs = FileItem(name: "logs", path: "/var/log/logs", isDirectory: true)
        let remoteFileSystem = MockRemoteFileSystem(
            listingsByPath: [
                "/var/log/logs": [
                    FileItem(name: "app.log", path: "/var/log/logs/app.log", isDirectory: false, size: 42),
                    FileItem(name: "archive", path: "/var/log/logs/archive", isDirectory: true)
                ],
                "/var/log/logs/archive": [
                    FileItem(name: "old.log", path: "/var/log/logs/archive/old.log", isDirectory: false, size: 56)
                ]
            ]
        )
        let hostSessionManager = HostSessionManager(
            remoteFileSystem: remoteFileSystem,
            credentialStore: InMemoryCredentialStore(),
            defaultLocalPath: { "/Users/me/Downloads" }
        )
        let planner = DirectoryTransferPlanner(localFileSystem: FakePlannerLocalFileSystem())

        let tasks = try await planner.downloadTasks(
            for: [logs],
            host: host,
            localDirectory: "/Users/me/Downloads",
            hostSessionManager: hostSessionManager
        )

        XCTAssertEqual(tasks.map(\.remotePath), [
            "/var/log/logs/app.log",
            "/var/log/logs/archive/old.log"
        ])
        XCTAssertEqual(tasks.map(\.localPath), [
            "/Users/me/Downloads/logs/app.log",
            "/Users/me/Downloads/logs/archive/old.log"
        ])
        XCTAssertEqual(tasks.map(\.fileName), ["app.log", "old.log"])
        XCTAssertEqual(tasks.map(\.totalBytes), [42, 56])
        XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), [
            "/var/log/logs",
            "/var/log/logs/archive"
        ])
    }
}

private final class FakePlannerLocalFileSystem: LocalFileSystem, @unchecked Sendable {
    var listingsByPath: [String: [FileItem]]
    private(set) var listCalls: [String] = []

    init(listingsByPath: [String: [FileItem]] = [:]) {
        self.listingsByPath = listingsByPath
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        listCalls.append(path)
        return listingsByPath[path] ?? []
    }

    func copyItem(at sourcePath: String, to destinationPath: String) throws {}

    func deleteItem(at path: String) throws {}
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
