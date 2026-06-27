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

    func testConfiguredRealHostsUploadAndDownloadFilesAndDirectories() async throws {
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
                try await transferE2E(host: host, environment: environment)
            } catch {
                failures.append(String(describing: error))
            }
        }

        XCTAssertTrue(failures.isEmpty, failures.joined(separator: "\n"))
    }

    func testConfiguredOpenCloudHostUploadsUnicodeDirectoryFilesWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WETRANS_REAL_UPLOAD_SMOKE"] == "1" else {
            throw XCTSkip("Set WETRANS_REAL_UPLOAD_SMOKE=1 to write upload smoke files to OpenCloud VM.")
        }

        let configURL = try Self.configURL(environment: environment)
        let config = try SFTPIntegrationConfig.load(from: configURL)
        let host = try XCTUnwrap(config.hosts.first { $0.name == "openclaw-vm" })

        try await uploadUnicodeSmokeFiles(host: host, environment: environment)
    }

    func testConfiguredOpenCloudHostUploadsUnicodeDirectoryThroughTransferQueueWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WETRANS_REAL_UPLOAD_SMOKE"] == "1" else {
            throw XCTSkip("Set WETRANS_REAL_UPLOAD_SMOKE=1 to write upload smoke files to OpenCloud VM.")
        }

        let configURL = try Self.configURL(environment: environment)
        let config = try SFTPIntegrationConfig.load(from: configURL)
        let host = try XCTUnwrap(config.hosts.first { $0.name == "openclaw-vm" })

        try await uploadUnicodeSmokeDirectoryThroughQueue(host: host, environment: environment)
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

    private func uploadUnicodeSmokeFiles(host: SFTPIntegrationHost, environment: [String: String]) async throws {
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

        let localDirectory = temporaryDirectory().appendingPathComponent("unicode-upload", isDirectory: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        let fileNames = [
            "滴滴出行行程报销单.pdf",
            "滴滴电子发票.pdf",
            "雅乐轩-酒店.pdf",
            "雅乐轩-水单.jpg"
        ]
        for (index, fileName) in fileNames.enumerated() {
            let data = Data("wetrans unicode upload smoke \(index)\n".utf8)
            try data.write(to: localDirectory.appendingPathComponent(fileName))
        }

        let remoteDirectory = "/tmp/wetrans-upload-smoke-\(UUID().uuidString)"
        let adapter = LibSSH2RemoteFileSystem(trustedHostStore: trustedStore)
        let session = try await connect(
            adapter: adapter,
            spec: spec,
            trustedStore: trustedStore,
            host: host,
            hostId: hostId
        )
        defer {
            Task {
                await adapter.disconnect(session)
            }
        }

        try await adapter.ensureDirectory(remoteDirectory, in: session)
        var failures: [String] = []
        for fileName in fileNames {
            let localPath = localDirectory.appendingPathComponent(fileName).path
            let remotePath = "\(remoteDirectory)/\(fileName)"
            do {
                try await adapter.upload(
                    UploadRequest(localPath: localPath, remotePath: remotePath),
                    in: session,
                    progress: { _ in }
                )
            } catch {
                failures.append("\(fileName): \(error.localizedDescription)")
            }
        }

        let uploadedItems = try await adapter.listDirectory(remoteDirectory, in: session)
        XCTAssertEqual(Set(uploadedItems.map(\.name)), Set(fileNames))
        XCTAssertTrue(failures.isEmpty, "Remote directory: \(remoteDirectory)\n" + failures.joined(separator: "\n"))
    }

    private func uploadUnicodeSmokeDirectoryThroughQueue(
        host: SFTPIntegrationHost,
        environment: [String: String]
    ) async throws {
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

        let localRoot = temporaryDirectory()
        let localDirectory = localRoot.appendingPathComponent("0624报销", isDirectory: true)
        try FileManager.default.createDirectory(at: localDirectory, withIntermediateDirectories: true)
        let fileNames = [
            "滴滴出行行程报销单.pdf",
            "滴滴电子发票.pdf",
            "雅乐轩-酒店.pdf",
            "雅乐轩-水单.jpg"
        ]
        for (index, fileName) in fileNames.enumerated() {
            let payload = Data(repeating: UInt8(index + 1), count: 96 * 1024)
            try payload.write(to: localDirectory.appendingPathComponent(fileName))
        }

        let savedHost = SavedHost(
            id: hostId,
            source: .manual,
            displayName: host.name,
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            authType: .sshKey,
            identityFile: host.expandedIdentityFile
        )
        let remoteRoot = "/tmp/wetrans-queue-upload-smoke-\(UUID().uuidString)"
        let planner = DirectoryTransferPlanner(localFileSystem: FileManagerLocalFileSystem())
        let tasks = try planner.uploadTasks(
            for: [
                FileItem(name: localDirectory.lastPathComponent, path: localDirectory.path, isDirectory: true)
            ],
            host: savedHost,
            remoteDirectory: remoteRoot
        )
        XCTAssertEqual(tasks.count, fileNames.count)

        let adapter = LibSSH2RemoteFileSystem(trustedHostStore: trustedStore)
        let connectionProvider = StaticSpecTransferConnectionProvider(
            spec: spec,
            adapter: adapter,
            trustedStore: trustedStore,
            integrationHost: host
        )
        let queue = TransferQueue(
            engine: SFTPTransferEngine(connectionProvider: connectionProvider, remoteFileSystem: adapter),
            historyStore: EmptyTransferHistoryStore(),
            globalConcurrencyLimit: 3,
            perHostConcurrencyLimit: 2
        )

        await queue.enqueue(tasks)
        try await waitUntil(timeout: 20) {
            let statuses = await queue.snapshot().map(\.status)
            return statuses.allSatisfy { [.succeeded, .failed, .cancelled].contains($0) }
        }

        let snapshot = await queue.snapshot()
        let failures = snapshot
            .filter { $0.status != .succeeded }
            .map { "\($0.fileName): \($0.errorMessage ?? $0.status.rawValue)" }
        XCTAssertTrue(
            failures.isEmpty,
            "Remote root: \(remoteRoot)\n" + failures.joined(separator: "\n")
        )
    }

    private func transferE2E(host: SFTPIntegrationHost, environment: [String: String]) async throws {
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
            try await runTransferE2E(adapter: adapter, session: session, host: host)
            await adapter.disconnect(session)
        } catch {
            await adapter.disconnect(session)
            throw SFTPIntegrationError(host: host, operation: "upload/download E2E", underlying: error)
        }
    }

    private func runTransferE2E(
        adapter: LibSSH2RemoteFileSystem,
        session: RemoteSession,
        host: SFTPIntegrationHost
    ) async throws {
        _ = try await adapter.listDirectory(host.listPath, in: session)

        let fixture = try makeTransferE2EFixture()
        let remoteRoot = "/tmp/wetrans-e2e-\(UUID().uuidString)"
        let uploadsRoot = "\(remoteRoot)/uploads"
        let downloadRoot = temporaryDirectory().appendingPathComponent("downloads", isDirectory: true)

        try await adapter.ensureDirectory(remoteRoot, in: session)

        let remoteSingleDirectory = "\(uploadsRoot)/single"
        let remoteSinglePath = "\(remoteSingleDirectory)/single.txt"
        try await adapter.ensureDirectory(remoteSingleDirectory, in: session)
        try await adapter.upload(
            UploadRequest(localPath: fixture.single.path, remotePath: remoteSinglePath),
            in: session,
            progress: { _ in }
        )
        try await assertRemoteNames(["single.txt"], in: remoteSingleDirectory, adapter: adapter, session: session)

        let remoteMultipleDirectory = "\(uploadsRoot)/multiple"
        try await adapter.ensureDirectory(remoteMultipleDirectory, in: session)
        for localFile in fixture.multiple {
            try await adapter.upload(
                UploadRequest(
                    localPath: localFile.path,
                    remotePath: "\(remoteMultipleDirectory)/\(localFile.lastPathComponent)"
                ),
                in: session,
                progress: { _ in }
            )
        }
        try await assertRemoteNames(
            ["multi-a.txt", "multi-b.txt"],
            in: remoteMultipleDirectory,
            adapter: adapter,
            session: session
        )

        let remoteDirectoryRoot = "\(uploadsRoot)/directory"
        for (relativePath, _) in fixture.directoryContentsByRelativePath {
            let localPath = fixture.directory.appendingPathComponent(relativePath).path
            let remotePath = "\(remoteDirectoryRoot)/folder/\(relativePath)"
            try await adapter.ensureDirectory(BrowserPath.remoteParent(of: remotePath), in: session)
            try await adapter.upload(
                UploadRequest(localPath: localPath, remotePath: remotePath),
                in: session,
                progress: { _ in }
            )
        }
        try await assertRemoteNames(
            ["nested", "root-a.txt"],
            in: "\(remoteDirectoryRoot)/folder",
            adapter: adapter,
            session: session
        )
        try await assertRemoteNames(
            ["nested-a.txt", "nested-b.txt"],
            in: "\(remoteDirectoryRoot)/folder/nested",
            adapter: adapter,
            session: session
        )

        let downloadedSingle = downloadRoot.appendingPathComponent("single/single.txt")
        try await adapter.download(
            DownloadRequest(remotePath: remoteSinglePath, localPath: downloadedSingle.path),
            in: session,
            progress: { _ in }
        )
        XCTAssertEqual(
            try Data(contentsOf: downloadedSingle),
            try XCTUnwrap(fixture.contentsByLocalPath[fixture.single.path])
        )

        for localFile in fixture.multiple {
            let downloaded = downloadRoot
                .appendingPathComponent("multiple", isDirectory: true)
                .appendingPathComponent(localFile.lastPathComponent)
            try await adapter.download(
                DownloadRequest(
                    remotePath: "\(remoteMultipleDirectory)/\(localFile.lastPathComponent)",
                    localPath: downloaded.path
                ),
                in: session,
                progress: { _ in }
            )
            XCTAssertEqual(
                try Data(contentsOf: downloaded),
                try XCTUnwrap(fixture.contentsByLocalPath[localFile.path])
            )
        }

        for (relativePath, expectedData) in fixture.directoryContentsByRelativePath {
            let downloaded = downloadRoot
                .appendingPathComponent("directory/folder", isDirectory: true)
                .appendingPathComponent(relativePath)
            try await adapter.download(
                DownloadRequest(
                    remotePath: "\(remoteDirectoryRoot)/folder/\(relativePath)",
                    localPath: downloaded.path
                ),
                in: session,
                progress: { _ in }
            )
            XCTAssertEqual(try Data(contentsOf: downloaded), expectedData)
        }
    }

    private func assertRemoteNames(
        _ expectedNames: Set<String>,
        in path: String,
        adapter: LibSSH2RemoteFileSystem,
        session: RemoteSession
    ) async throws {
        let items = try await adapter.listDirectory(path, in: session)
        XCTAssertEqual(Set(items.map(\.name)), expectedNames)
    }

    private func makeTransferE2EFixture() throws -> TransferE2EFixture {
        let sourceRoot = temporaryDirectory().appendingPathComponent("source", isDirectory: true)
        let folder = sourceRoot.appendingPathComponent("folder", isDirectory: true)
        let nested = folder.appendingPathComponent("nested", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)

        let files: [(URL, Data)] = [
            (sourceRoot.appendingPathComponent("single.txt"), Data("wetrans e2e single\n".utf8)),
            (sourceRoot.appendingPathComponent("multi-a.txt"), Data("wetrans e2e multiple a\n".utf8)),
            (sourceRoot.appendingPathComponent("multi-b.txt"), Data("wetrans e2e multiple b\n".utf8)),
            (folder.appendingPathComponent("root-a.txt"), Data("wetrans e2e folder root\n".utf8)),
            (nested.appendingPathComponent("nested-a.txt"), Data("wetrans e2e nested a\n".utf8)),
            (nested.appendingPathComponent("nested-b.txt"), Data("wetrans e2e nested b\n".utf8))
        ]

        var contentsByLocalPath: [String: Data] = [:]
        for (url, data) in files {
            try data.write(to: url)
            contentsByLocalPath[url.path] = data
        }

        return TransferE2EFixture(
            sourceRoot: sourceRoot,
            single: sourceRoot.appendingPathComponent("single.txt"),
            multiple: [
                sourceRoot.appendingPathComponent("multi-a.txt"),
                sourceRoot.appendingPathComponent("multi-b.txt")
            ],
            directory: folder,
            directoryContentsByRelativePath: [
                "root-a.txt": Data("wetrans e2e folder root\n".utf8),
                "nested/nested-a.txt": Data("wetrans e2e nested a\n".utf8),
                "nested/nested-b.txt": Data("wetrans e2e nested b\n".utf8)
            ],
            contentsByLocalPath: contentsByLocalPath
        )
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

private final class StaticSpecTransferConnectionProvider: TransferConnectionProvider, @unchecked Sendable {
    private let spec: ConnectionSpec
    private let adapter: LibSSH2RemoteFileSystem
    private let trustedStore: TrustedHostStore
    private let integrationHost: SFTPIntegrationHost

    init(
        spec: ConnectionSpec,
        adapter: LibSSH2RemoteFileSystem,
        trustedStore: TrustedHostStore,
        integrationHost: SFTPIntegrationHost
    ) {
        self.spec = spec
        self.adapter = adapter
        self.trustedStore = trustedStore
        self.integrationHost = integrationHost
    }

    func connect(hostId: UUID) async throws -> RemoteSession {
        do {
            return try await adapter.connect(spec)
        } catch RemoteFileSystemError.hostKeyRequiresTrust(let candidate)
            where integrationHost.trustedHostKey(hostId: hostId) == nil
        {
            try trustedStore.trust(candidate)
            return try await adapter.connect(spec)
        }
    }

    func disconnect(_ session: RemoteSession) async {
        await adapter.disconnect(session)
    }
}

private func waitUntil(
    timeout: TimeInterval,
    condition: @escaping () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 20_000_000)
    }
    XCTFail("Timed out waiting for condition")
}

private struct SFTPIntegrationConfig: Decodable {
    let hosts: [SFTPIntegrationHost]

    static func load(from url: URL) throws -> SFTPIntegrationConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(SFTPIntegrationConfig.self, from: data)
    }
}

private struct TransferE2EFixture {
    let sourceRoot: URL
    let single: URL
    let multiple: [URL]
    let directory: URL
    let directoryContentsByRelativePath: [String: Data]
    let contentsByLocalPath: [String: Data]
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
