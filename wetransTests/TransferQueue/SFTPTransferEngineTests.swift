import Foundation
import XCTest
@testable import wetrans

final class SFTPTransferEngineTests: XCTestCase {
    func testUploadTaskOpensSessionUploadsAndDisconnects() async throws {
        let host = SavedHost.fixture()
        let session = RemoteSession(hostId: host.id, displayName: host.displayName)
        let remoteFileSystem = MockRemoteFileSystem()
        let provider = FakeTransferConnectionProvider(hostsById: [host.id: host], session: session)
        let engine = SFTPTransferEngine(connectionProvider: provider, remoteFileSystem: remoteFileSystem)
        let task = makeTask(host: host, direction: .upload, localPath: "/Users/me/config.yaml", remotePath: "/etc/config.yaml")
        let recorder = ProgressRecorder()

        try await engine.run(task: task) { progress in
            await recorder.append(progress)
        }

        XCTAssertEqual(provider.connectCalls, [host.id])
        XCTAssertEqual(remoteFileSystem.uploadCalls, [
            .init(request: UploadRequest(localPath: "/Users/me/config.yaml", remotePath: "/etc/config.yaml"), session: session)
        ])
        XCTAssertEqual(provider.disconnectCalls, [session])
        let recordedEvents = await recorder.events
        XCTAssertEqual(recordedEvents, [])
    }

    func testDownloadTaskOpensSessionDownloadsAndForwardsProgress() async throws {
        let host = SavedHost.fixture()
        let session = RemoteSession(hostId: host.id, displayName: host.displayName)
        let progress = TransferProgress(transferredBytes: 5, totalBytes: 10, speedBytesPerSecond: 2)
        let remoteFileSystem = MockRemoteFileSystem(downloadProgressEvents: [progress])
        let provider = FakeTransferConnectionProvider(hostsById: [host.id: host], session: session)
        let engine = SFTPTransferEngine(connectionProvider: provider, remoteFileSystem: remoteFileSystem)
        let task = makeTask(host: host, direction: .download, localPath: "/Users/me/app.log", remotePath: "/var/log/app.log")
        let recorder = ProgressRecorder()

        try await engine.run(task: task) { progress in
            await recorder.append(progress)
        }

        XCTAssertEqual(remoteFileSystem.downloadCalls, [
            .init(request: DownloadRequest(remotePath: "/var/log/app.log", localPath: "/Users/me/app.log"), session: session)
        ])
        XCTAssertEqual(provider.disconnectCalls, [session])
        let recordedEvents = await recorder.events
        XCTAssertEqual(recordedEvents, [progress])
    }

    func testDisconnectsWhenTransferFails() async {
        let host = SavedHost.fixture()
        let session = RemoteSession(hostId: host.id, displayName: host.displayName)
        let remoteFileSystem = MockRemoteFileSystem()
        remoteFileSystem.uploadError = RemoteFileSystemError.permissionDenied("/etc")
        let provider = FakeTransferConnectionProvider(hostsById: [host.id: host], session: session)
        let engine = SFTPTransferEngine(connectionProvider: provider, remoteFileSystem: remoteFileSystem)
        let task = makeTask(host: host, direction: .upload)

        await XCTAssertThrowsErrorAsync(try await engine.run(task: task) { _ in }) { error in
            XCTAssertEqual(error as? RemoteFileSystemError, .permissionDenied("/etc"))
        }
        XCTAssertEqual(provider.disconnectCalls, [session])
    }

    func testMissingHostThrowsReadableError() async {
        let hostId = UUID()
        let provider = FakeTransferConnectionProvider(hostsById: [:], session: RemoteSession(hostId: hostId, displayName: "missing"))
        let engine = SFTPTransferEngine(connectionProvider: provider, remoteFileSystem: MockRemoteFileSystem())
        let task = TransferTask(
            hostId: hostId,
            hostDisplayName: "missing",
            direction: .download,
            localPath: "/Users/me/a",
            remotePath: "/tmp/a",
            fileName: "a",
            totalBytes: nil
        )

        await XCTAssertThrowsErrorAsync(try await engine.run(task: task) { _ in }) { error in
            XCTAssertEqual(error as? SFTPTransferEngineError, .hostNotFound(hostId))
        }
    }
}

private final class FakeTransferConnectionProvider: TransferConnectionProvider, @unchecked Sendable {
    let hostsById: [UUID: SavedHost]
    let session: RemoteSession
    private(set) var connectCalls: [UUID] = []
    private(set) var disconnectCalls: [RemoteSession] = []

    init(hostsById: [UUID: SavedHost], session: RemoteSession) {
        self.hostsById = hostsById
        self.session = session
    }

    func connect(hostId: UUID) async throws -> RemoteSession {
        guard hostsById[hostId] != nil else {
            throw SFTPTransferEngineError.hostNotFound(hostId)
        }
        connectCalls.append(hostId)
        return session
    }

    func disconnect(_ session: RemoteSession) async {
        disconnectCalls.append(session)
    }
}

private actor ProgressRecorder {
    private var recordedEvents: [TransferProgress] = []

    var events: [TransferProgress] {
        recordedEvents
    }

    func append(_ progress: TransferProgress) {
        recordedEvents.append(progress)
    }
}

private func makeTask(
    host: SavedHost,
    direction: TransferDirection,
    localPath: String = "/Users/me/file.txt",
    remotePath: String = "/home/ubuntu/file.txt"
) -> TransferTask {
    TransferTask(
        hostId: host.id,
        hostDisplayName: host.displayName,
        direction: direction,
        localPath: localPath,
        remotePath: remotePath,
        fileName: URL(fileURLWithPath: localPath).lastPathComponent,
        totalBytes: 10
    )
}

private extension SavedHost {
    static func fixture(id: UUID = UUID(), displayName: String = "dev") -> SavedHost {
        SavedHost(
            id: id,
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            port: 22,
            username: "ubuntu",
            authType: .password
        )
    }
}

private func XCTAssertThrowsErrorAsync<T>(
    _ expression: @autoclosure () async throws -> T,
    _ verify: (Error) -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        _ = try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        verify(error)
    }
}
