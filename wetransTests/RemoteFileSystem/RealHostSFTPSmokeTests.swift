import Foundation
import XCTest
@testable import wetrans

final class RealHostSFTPSmokeTests: XCTestCase {
    func testCommittedFixtureDecodesExpectedHosts() throws {
        let config = try RealHostSmokeConfig.load(from: Self.defaultConfigURL())

        XCTAssertEqual(config.hosts.map(\.name), ["openclaw-vm", "xfh-cmg-es"])
        XCTAssertEqual(config.hosts.first { $0.name == "openclaw-vm" }?.identityFile, "~/.ssh/openclaw_vm")
        XCTAssertEqual(config.hosts.first { $0.name == "xfh-cmg-es" }?.listPath, "/data")
        XCTAssertTrue(config.hosts.allSatisfy { !$0.identityFile.contains("BEGIN ") })
    }

    func testConfiguredRealHostsConnectAndListWhenEnabled() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["WETRANS_RUN_REAL_HOST_SMOKE"] == "1" else {
            throw XCTSkip(
                "Set WETRANS_RUN_REAL_HOST_SMOKE=1 to run real host SFTP smoke. See docs/real-host-sftp-smoke.md."
            )
        }

        let configURL = try Self.configURL(environment: environment)
        let config = try RealHostSmokeConfig.load(from: configURL)
        guard !config.hosts.isEmpty else {
            XCTFail("Real host smoke config has no hosts: \(configURL.path)")
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
        host: RealHostSmokeHost,
        hostId: UUID
    ) async throws -> RemoteSession {
        do {
            return try await adapter.connect(spec)
        } catch RemoteFileSystemError.hostKeyRequiresTrust(let candidate) where host.trustedHostKey(hostId: hostId) == nil {
            try trustedStore.trust(candidate)
            return try await adapter.connect(spec)
        }
    }

    private func smoke(host: RealHostSmokeHost, environment: [String: String]) async throws {
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
            throw RealHostSmokeError(host: host, operation: "connect", underlying: error)
        }

        do {
            _ = try await adapter.listDirectory(host.listPath, in: session)
        } catch {
            await adapter.disconnect(session)
            throw RealHostSmokeError(host: host, operation: "list \(host.listPath)", underlying: error)
        }

        await adapter.disconnect(session)
    }

    private static func defaultConfigURL() -> URL {
        guard let url = Bundle.module.url(
            forResource: "real-host-smoke.example",
            withExtension: "json",
            subdirectory: "Fixtures"
        ) else {
            XCTFail("Missing bundled real host smoke fixture")
            return URL(fileURLWithPath: "/missing-real-host-smoke-fixture.json")
        }
        return url
    }

    private static func configURL(environment: [String: String]) throws -> URL {
        if let path = environment["WETRANS_REAL_HOSTS_FILE"], !path.isEmpty {
            return URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        }
        return defaultConfigURL()
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wetrans-real-host-smoke-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

private struct RealHostSmokeConfig: Decodable {
    let hosts: [RealHostSmokeHost]

    static func load(from url: URL) throws -> RealHostSmokeConfig {
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(RealHostSmokeConfig.self, from: data)
    }
}

private struct RealHostSmokeHost: Decodable {
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

private struct RealHostSmokeError: Error, CustomStringConvertible {
    let host: RealHostSmokeHost
    let operation: String
    let underlying: Error

    var description: String {
        "Real host SFTP smoke failed for \(host.name) (\(host.username)@\(host.hostname):\(host.port), path \(host.listPath)) during \(operation): \(underlying)"
    }
}
