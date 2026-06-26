import XCTest
@testable import wetrans

final class LibSSH2RemoteFileSystemTests: XCTestCase {
    func testConnectInitializesRuntimeAndThrowsUnsupportedOperation() async {
        let runtime = FakeLibSSH2Runtime()
        let adapter = LibSSH2RemoteFileSystem(runtime: runtime)
        let spec = ConnectionSpec(
            hostId: UUID(),
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            auth: .password(nil),
            defaultRemotePath: "~"
        )

        await XCTAssertThrowsErrorAsync(try await adapter.connect(spec)) { error in
            XCTAssertEqual(error as? LibSSH2Error, .operationUnsupported("libssh2 SFTP connect is not implemented yet"))
        }
        XCTAssertEqual(runtime.initializeCallCount, 1)
    }

    func testListDirectoryThrowsDisconnected() async {
        let adapter = LibSSH2RemoteFileSystem(runtime: FakeLibSSH2Runtime())
        let session = RemoteSession(hostId: UUID(), displayName: "dev")

        await XCTAssertThrowsErrorAsync(try await adapter.listDirectory("/", in: session)) { error in
            XCTAssertEqual(error as? RemoteFileSystemError, .disconnected)
        }
    }

    func testDisconnectShutsDownRuntime() async {
        let runtime = FakeLibSSH2Runtime()
        let adapter = LibSSH2RemoteFileSystem(runtime: runtime)
        let session = RemoteSession(hostId: UUID(), displayName: "dev")

        await adapter.disconnect(session)

        XCTAssertEqual(runtime.shutdownCallCount, 1)
    }
}

private final class FakeLibSSH2Runtime: LibSSH2RuntimeManaging {
    private(set) var initializeCallCount = 0
    private(set) var shutdownCallCount = 0

    func initialize() throws -> LibSSH2LibraryInfo {
        initializeCallCount += 1
        return LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: "1.11.1")
    }

    func shutdown() {
        shutdownCallCount += 1
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

