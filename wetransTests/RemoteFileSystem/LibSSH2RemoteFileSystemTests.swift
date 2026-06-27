import Foundation
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

    func testUploadDelegatesToConnectedClient() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let client = FakeLibSSH2Client(hostKey: candidate)
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: candidate),
            clientFactory: FakeLibSSH2ClientFactory(client: client)
        )
        let session = try await adapter.connect(spec)
        let request = UploadRequest(localPath: "/tmp/config.yaml", remotePath: "/etc/config.yaml")

        try await adapter.upload(request, in: session) { _ in }

        XCTAssertEqual(client.uploadCalls, [request])
    }

    func testEnsureDirectoryDelegatesToConnectedClient() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let client = FakeLibSSH2Client(hostKey: candidate)
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: candidate),
            clientFactory: FakeLibSSH2ClientFactory(client: client)
        )
        let session = try await adapter.connect(spec)

        try await adapter.ensureDirectory("/var/www/site", in: session)

        XCTAssertEqual(client.ensureDirectoryCalls, ["/var/www/site"])
    }

    func testDownloadDelegatesToConnectedClient() async throws {
        let hostId = UUID()
        let spec = makeSpec(hostId: hostId)
        let candidate = makeTrustedKey(hostId: hostId, fingerprint: "SHA256:candidate")
        let client = FakeLibSSH2Client(hostKey: candidate)
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: candidate),
            clientFactory: FakeLibSSH2ClientFactory(client: client)
        )
        let session = try await adapter.connect(spec)
        let request = DownloadRequest(remotePath: "/var/log/app.log", localPath: "/tmp/app.log")

        try await adapter.download(request, in: session) { _ in }

        XCTAssertEqual(client.downloadCalls, [request])
    }

    func testUploadAndDownloadThrowDisconnectedWithoutConnectedClient() async {
        let adapter = LibSSH2RemoteFileSystem(
            runtime: FakeLibSSH2Runtime(),
            trustedHostStore: FakeTrustedHostStore(trustedKey: nil),
            clientFactory: FakeLibSSH2ClientFactory(client: FakeLibSSH2Client(hostKey: makeTrustedKey()))
        )
        let session = RemoteSession(hostId: UUID(), displayName: "dev")

        await XCTAssertThrowsErrorAsync(
            try await adapter.upload(UploadRequest(localPath: "/tmp/a", remotePath: "/tmp/a"), in: session) { _ in }
        ) { error in
            XCTAssertEqual(error as? RemoteFileSystemError, .disconnected)
        }
        await XCTAssertThrowsErrorAsync(
            try await adapter.download(DownloadRequest(remotePath: "/tmp/a", localPath: "/tmp/a"), in: session) { _ in }
        ) { error in
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

final class RemoteFileSystemRealHostIntegrationTests: XCTestCase {
    func testCommittedFixtureDecodesOpenclawVM() throws {
        let config = try SFTPIntegrationConfig.load(from: Self.defaultConfigURL())

        XCTAssertEqual(config.hosts.map(\.name), ["openclaw-vm"])
        XCTAssertEqual(config.hosts[0].hostname, "43.164.133.39")
        XCTAssertEqual(config.hosts[0].username, "ubuntu")
        XCTAssertEqual(config.hosts[0].identityFile, "~/.ssh/openclaw_vm")
        XCTAssertEqual(config.hosts[0].listPath, ".")
        XCTAssertFalse(config.hosts[0].identityFile.contains("BEGIN "))
    }

    func testConfiguredRealHostsConnectAndList() async throws {
        let environment = ProcessInfo.processInfo.environment
        let configURL = try Self.configURL(environment: environment)
        let config = try SFTPIntegrationConfig.load(from: configURL)
        guard !config.hosts.isEmpty else {
            XCTFail("SFTP integration config has no hosts: \(configURL.path)")
            return
        }

        var failures: [String] = []
        for host in config.hosts {
            do {
                try await smoke(host: host, environment: environment)
            } catch {
                failures.append(String(describing: error))
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    private func connect(
        adapter: LibSSH2RemoteFileSystem,
        spec: ConnectionSpec,
        trustedStore: TrustedHostStore,
        host: SFTPIntegrationHost,
        hostId: UUID
    ) async throws -> RemoteSession {
        do {
            return try await adapter.connect(spec)
        } catch RemoteFileSystemError.hostKeyRequiresTrust(let candidate) where host.trustedHostKey(hostId: hostId) == nil {
            try trustedStore.trust(candidate)
            return try await adapter.connect(spec)
        }
    }

    private func smoke(host: SFTPIntegrationHost, environment: [String: String]) async throws {
        let hostId = UUID()
        let spec = ConnectionSpec(
            hostId: hostId,
            displayName: host.name,
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            auth: .sshKey(
                identityFile: host.expandedIdentityFile,
                passphrase: host.passphrase(environment: environment)
            ),
            defaultRemotePath: host.listPath
        )
        let trustedStore = FileTrustedHostStore(applicationSupportDirectory: temporaryDirectory())
        if let trustedKey = host.trustedHostKey(hostId: hostId) {
            try trustedStore.trust(trustedKey)
        }

        let adapter = LibSSH2RemoteFileSystem(trustedHostStore: trustedStore)
        let session: RemoteSession
        do {
            session = try await connect(
                adapter: adapter,
                spec: spec,
                trustedStore: trustedStore,
                host: host,
                hostId: hostId
            )
        } catch {
            throw SFTPIntegrationError(host: host, operation: "connect", underlying: error)
        }

        do {
            _ = try await adapter.listDirectory(host.listPath, in: session)
        } catch {
            await adapter.disconnect(session)
            throw SFTPIntegrationError(host: host, operation: "list \(host.listPath)", underlying: error)
        }

        await adapter.disconnect(session)
    }

    private static func defaultConfigURL() -> URL {
        guard let url = Bundle.module.url(
            forResource: "real-host-smoke.example",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("Missing bundled real SFTP integration fixture")
            return URL(fileURLWithPath: "/missing-real-sftp-integration-fixture.json")
        }
        return url
    }

    private static func configURL(environment: [String: String]) throws -> URL {
        if let path = environment["WETRANS_SFTP_INTEGRATION_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return defaultConfigURL()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wetrans-sftp-integration-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct SFTPIntegrationConfig: Decodable {
    let hosts: [SFTPIntegrationHost]

    static func load(from url: URL) throws -> SFTPIntegrationConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SFTPIntegrationConfig.self, from: data)
    }
}

private struct SFTPIntegrationHost: Decodable {
    let name: String
    let hostname: String
    let port: Int
    let username: String
    let identityFile: String
    let listPath: String
    let passphraseEnv: String?
    let hostKeyType: String?
    let hostKeyFingerprintSHA256: String?

    var expandedIdentityFile: String {
        (identityFile as NSString).expandingTildeInPath
    }

    func passphrase(environment: [String: String]) -> String? {
        guard let passphraseEnv, !passphraseEnv.isEmpty else {
            return nil
        }
        return environment[passphraseEnv].flatMap { $0.isEmpty ? nil : $0 }
    }

    func trustedHostKey(hostId: UUID) -> TrustedHostKey? {
        guard let hostKeyType, let hostKeyFingerprintSHA256 else {
            return nil
        }
        let now = Date()
        return TrustedHostKey(
            hostId: hostId,
            hostname: hostname,
            port: port,
            keyType: hostKeyType,
            fingerprintSHA256: hostKeyFingerprintSHA256,
            firstTrustedAt: now,
            lastVerifiedAt: now
        )
    }
}

private struct SFTPIntegrationError: Error, CustomStringConvertible {
    let host: SFTPIntegrationHost
    let operation: String
    let underlying: Error

    var description: String {
        "Real SFTP integration failed for \(host.name) (\(host.username)@\(host.hostname):\(host.port), path \(host.listPath)) during \(operation): \(underlying)"
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
    private(set) var ensureDirectoryCalls: [String] = []
    private(set) var uploadCalls: [UploadRequest] = []
    private(set) var downloadCalls: [DownloadRequest] = []
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

    func ensureDirectory(_ path: String) throws {
        ensureDirectoryCalls.append(path)
    }

    func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        uploadCalls.append(request)
    }

    func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        downloadCalls.append(request)
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
