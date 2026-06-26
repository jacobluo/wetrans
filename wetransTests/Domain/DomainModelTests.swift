import XCTest
@testable import wetrans

final class DomainModelTests: XCTestCase {
    func testSavedHostCodableUsesPersistedFieldsWithoutSecrets() throws {
        let host = SavedHost(
            id: UUID(uuidString: "8C765C99-6B46-4D74-BB3C-2B71F21997C6")!,
            source: .sshConfigGenerated,
            displayName: "dev",
            hostname: "192.0.2.10",
            username: "ubuntu",
            authType: .sshKey,
            identityFile: "/Users/example/.ssh/id_ed25519",
            isFavorite: true,
            lastConnectedAt: Date(timeIntervalSince1970: 1_782_460_800),
            lastRemotePath: "/home/ubuntu/project",
            lastLocalPath: "/Users/example/Downloads",
            defaultRemotePath: "/home/ubuntu",
            favoriteRemotePaths: ["/home/ubuntu/project", "/var/log"],
            originSSHConfigAlias: "dev",
            resolvedAt: Date(timeIntervalSince1970: 1_782_460_700),
            note: "Development server"
        )

        let data = try JSONEncoder.wetransDefault.encode(host)
        let json = String(decoding: data, as: UTF8.self)

        XCTAssertTrue(json.contains("\"originSSHConfigAlias\" : \"dev\""))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("password"))
        XCTAssertFalse(json.localizedCaseInsensitiveContains("passphrase"))
        XCTAssertEqual(try JSONDecoder.wetransDefault.decode(SavedHost.self, from: data), host)
    }

    func testTransferTaskCodableRoundTrips() throws {
        let task = TransferTask(
            id: UUID(uuidString: "AFB0EE91-3E6D-4B43-B3E5-00F9551162A6")!,
            hostId: UUID(uuidString: "8C765C99-6B46-4D74-BB3C-2B71F21997C6")!,
            hostDisplayName: "dev",
            direction: .upload,
            localPath: "/Users/example/Downloads/config.yaml",
            remotePath: "/home/ubuntu/project/config.yaml",
            fileName: "config.yaml",
            totalBytes: 8421,
            transferredBytes: 8421,
            progress: 1,
            speedBytesPerSecond: 1_200_000,
            status: .succeeded,
            createdAt: Date(timeIntervalSince1970: 1_782_461_100),
            startedAt: Date(timeIntervalSince1970: 1_782_461_101),
            completedAt: Date(timeIntervalSince1970: 1_782_461_103)
        )

        let data = try JSONEncoder.wetransDefault.encode(task)

        XCTAssertEqual(try JSONDecoder.wetransDefault.decode(TransferTask.self, from: data), task)
    }
}

