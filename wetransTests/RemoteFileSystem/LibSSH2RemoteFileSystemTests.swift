import XCTest
@testable import wetrans

final class LibSSH2RemoteFileSystemTests: XCTestCase {
    func testConnectInitializesRuntimeVerifiesTrustedHostAndAuthenticates() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let trusted = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let runtime = FakeLibSSH2Runtime()
        let trustedStore = FakeTrustedHostStore(trustedKey: trusted)
        let factory = FakeLibSSH2ClientFactory(client: FakeLibSSH2Client(hostKey: candidate))
        let adapter = LibSSH2RemoteFileSystem(
            runtime: runtime,
            trustedHostStore: trustedStore,
            clientFactory: factory
        )

        let session = try await adapter.connect(spec)

        XCTAssertEqual(runtime.initializeCallCount, 1)
        XCTAssertEqual(factory.makeClientCallCount, 1)
        XCTAssertEqual(factory.clients[0].connectCalls, [spec])
        XCTAssertEqual(factory.clients[0].authenticateCalls, [spec.auth])
        XCTAssertEqual(factory.clients[0].openSFTPCallCount, 1)
        XCTAssertEqual(session.hostId, spec.hostId)
        XCTAssertEqual(session.displayName, spec.displayName)
        XCTAssertEqual(trustedStore.recordVerificationCalls.count, 1)
        XCTAssertEqual(trustedStore.recordVerificationCalls[0].hostId, spec.hostId)
        XCTAssertEqual(trustedStore.recordVerificationCalls[0].hostname, spec.hostname)
        XCTAssertEqual(trustedStore.recordVerificationCalls[0].port, spec.port)
    }

    func testConnectThrowsHostKeyRequiresTrustForUnknownHost() async {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let factory = FakeLibSSH2ClientFactory(client: FakeLibSSH2Client(hostKey: candidate))
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: nil),
            clientFactory: factory
        )

        await XCTAssertThrowsErrorAsync(try await adapter.connect(spec)) { error in
            guard case .hostKeyRequiresTrust(let actual)? = error as? RemoteFileSystemError else {
                return XCTFail("Expected hostKeyRequiresTrust, got \(error)")
            }
            XCTAssertEqual(actual.hostId, candidate.hostId)
            XCTAssertEqual(actual.hostname, candidate.hostname)
            XCTAssertEqual(actual.port, candidate.port)
            XCTAssertEqual(actual.keyType, candidate.keyType)
            XCTAssertEqual(actual.fingerprintSHA256, candidate.fingerprintSHA256)
        }
        XCTAssertEqual(factory.clients[0].authenticateCalls, [])
        XCTAssertEqual(factory.clients[0].disconnectCallCount, 1)
    }

    func testConnectThrowsHostKeyChangedForChangedHostKey() async {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let trusted = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:trusted")
        let changed = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:changed")
        let factory = FakeLibSSH2ClientFactory(client: FakeLibSSH2Client(hostKey: changed))
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: trusted),
            clientFactory: factory
        )

        await XCTAssertThrowsErrorAsync(try await adapter.connect(spec)) { error in
            guard case .hostKeyChanged(let expected, let actual)? = error as? RemoteFileSystemError else {
                return XCTFail("Expected hostKeyChanged, got \(error)")
            }
            XCTAssertEqual(expected, trusted)
            XCTAssertEqual(actual.hostId, changed.hostId)
            XCTAssertEqual(actual.hostname, changed.hostname)
            XCTAssertEqual(actual.port, changed.port)
            XCTAssertEqual(actual.keyType, changed.keyType)
            XCTAssertEqual(actual.fingerprintSHA256, changed.fingerprintSHA256)
        }
        XCTAssertEqual(factory.clients[0].authenticateCalls, [])
        XCTAssertEqual(factory.clients[0].disconnectCallCount, 1)
    }

    func testListDirectoryUsesConnectedClient() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let items = [
            FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false)
        ]
        let client = FakeLibSSH2Client(hostKey: candidate, listingsByPath: ["/var/log": items])
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: candidate),
            clientFactory: FakeLibSSH2ClientFactory(client: client)
        )
        let session = try await adapter.connect(spec)

        let listing = try await adapter.listDirectory("/var/log", in: session)

        XCTAssertEqual(listing, items)
        XCTAssertEqual(client.listDirectoryCalls, ["/var/log"])
    }

    func testListDirectoryThrowsDisconnectedWithoutConnectedClient() async {
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: nil),
            clientFactory: FakeLibSSH2ClientFactory(client: FakeLibSSH2Client(hostKey: makeTrustedKey()))
        )
        let session = RemoteSession(hostId: UUID(), displayName: "dev")

        await XCTAssertThrowsErrorAsync(try await adapter.listDirectory("/", in: session)) { error in
            XCTAssertEqual(error as? RemoteFileSystemError, .disconnected)
        }
    }

    func testDisconnectClosesClientAndShutsDownRuntimeWhenLastSessionCloses() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let runtime = FakeLibSSH2Runtime()
        let client = FakeLibSSH2Client(hostKey: candidate)
        let adapter = LibSSH2RemoteFileSystem(
            runtime: runtime,
            trustedHostStore: FakeTrustedHostStore(trustedKey: candidate),
            clientFactory: FakeLibSSH2ClientFactory(client: client)
        )
        let session = try await adapter.connect(spec)

        await adapter.disconnect(session)

        XCTAssertEqual(client.disconnectCallCount, 1)
        XCTAssertEqual(runtime.shutdownCallCount, 1)
    }

    private func makeSpec(hostId: UUID = UUID()) -> ConnectionSpec {
        ConnectionSpec(
            hostId: hostId,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            auth: .password("secret"),
            defaultRemotePath: "~"
        )
    }

    private func makeTrustedKey(
        hostId: UUID = UUID(),
        fingerprint: String = "SHA256:candidate"
    ) -> TrustedHostKey {
        TrustedHostKey(
            hostId: hostId,
            hostname: "dev.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            fingerprintSHA256: fingerprint,
            firstTrustedAt: Date(timeIntervalSince1970: 1_700_000_000),
            lastVerifiedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
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

private final class FakeLibSSH2ClientFactory: LibSSH2ClientFactory {
    private(set) var makeClientCallCount = 0
    private(set) var clients: [FakeLibSSH2Client] = []
    private let client: FakeLibSSH2Client

    init(client: FakeLibSSH2Client) {
        self.client = client
    }

    func makeClient() -> LibSSH2Client {
        makeClientCallCount += 1
        clients.append(client)
        return client
    }
}

private final class FakeLibSSH2Client: LibSSH2Client {
    private let key: TrustedHostKey
    private let listingsByPath: [String: [FileItem]]
    private(set) var connectCalls: [ConnectionSpec] = []
    private(set) var authenticateCalls: [ConnectionAuth] = []
    private(set) var openSFTPCallCount = 0
    private(set) var listDirectoryCalls: [String] = []
    private(set) var disconnectCallCount = 0

    init(hostKey: TrustedHostKey, listingsByPath: [String: [FileItem]] = [:]) {
        self.key = hostKey
        self.listingsByPath = listingsByPath
    }

    func connect(_ spec: ConnectionSpec) throws {
        connectCalls.append(spec)
    }

    func hostKey(hostId: UUID, hostname: String, port: Int, at date: Date) throws -> TrustedHostKey {
        TrustedHostKey(
            id: key.id,
            hostId: hostId,
            hostname: hostname,
            port: port,
            keyType: key.keyType,
            fingerprintSHA256: key.fingerprintSHA256,
            firstTrustedAt: date,
            lastVerifiedAt: date
        )
    }

    func authenticate(username: String, auth: ConnectionAuth) throws {
        authenticateCalls.append(auth)
    }

    func openSFTP() throws {
        openSFTPCallCount += 1
    }

    func listDirectory(_ path: String) throws -> [FileItem] {
        listDirectoryCalls.append(path)
        return listingsByPath[path] ?? []
    }

    func disconnect() {
        disconnectCallCount += 1
    }
}

private final class FakeTrustedHostStore: TrustedHostStore {
    struct VerificationCall: Equatable {
        let hostId: UUID
        let hostname: String
        let port: Int
    }

    private let trustedKey: TrustedHostKey?
    private(set) var recordVerificationCalls: [VerificationCall] = []

    init(trustedKey: TrustedHostKey?) {
        self.trustedKey = trustedKey
    }

    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey? {
        trustedKey
    }

    func trust(_ key: TrustedHostKey) throws {}

    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws {
        recordVerificationCalls.append(VerificationCall(hostId: hostId, hostname: hostname, port: port))
    }

    func deleteKeys(hostId: UUID) throws {}
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
