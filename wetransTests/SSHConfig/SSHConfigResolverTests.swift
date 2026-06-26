import XCTest
@testable import wetrans

final class SSHConfigResolverTests: XCTestCase {
    func testParsesSSHResolvedOutput() throws {
        let output = """
        hostname dev.example.com
        user ubuntu
        port 22
        identityfile ~/.ssh/id_ed25519
        identityfile ~/.ssh/id_rsa
        proxyjump bastion
        """

        let resolved = try ProcessSSHConfigResolver.parse(alias: "dev", output: output)

        XCTAssertEqual(resolved.alias, "dev")
        XCTAssertEqual(resolved.hostname, "dev.example.com")
        XCTAssertEqual(resolved.user, "ubuntu")
        XCTAssertEqual(resolved.port, 22)
        XCTAssertEqual(resolved.identityFiles, ["~/.ssh/id_ed25519", "~/.ssh/id_rsa"])
        XCTAssertEqual(resolved.proxyJump, "bastion")
    }

    func testInvalidPortFails() {
        let output = """
        hostname dev.example.com
        port nope
        """

        XCTAssertThrowsError(try ProcessSSHConfigResolver.parse(alias: "dev", output: output)) { error in
            XCTAssertEqual(error as? SSHConfigResolverError, .invalidPort("nope"))
        }
    }

    func testMakesDraftFromResolvedConfig() {
        let resolvedAt = Date(timeIntervalSince1970: 50)
        let resolved = ResolvedSSHConfig(
            alias: "dev",
            hostname: "dev.example.com",
            user: "ubuntu",
            port: 22,
            identityFiles: ["~/.ssh/id_ed25519"],
            proxyJump: nil,
            proxyCommand: nil
        )

        let draft = ProcessSSHConfigResolver.makeDraft(from: resolved, resolvedAt: resolvedAt)

        XCTAssertEqual(draft.source, .sshConfigGenerated)
        XCTAssertEqual(draft.displayName, "dev")
        XCTAssertEqual(draft.hostname, "dev.example.com")
        XCTAssertEqual(draft.username, "ubuntu")
        XCTAssertEqual(draft.authType, .sshKey)
        XCTAssertEqual(draft.identityFile, "~/.ssh/id_ed25519")
        XCTAssertEqual(draft.originSSHConfigAlias, "dev")
        XCTAssertEqual(draft.resolvedAt, resolvedAt)
    }

    func testMakesUnsupportedWarningsForProxyOptions() {
        let resolved = ResolvedSSHConfig(
            alias: "prod",
            hostname: "prod.example.com",
            user: nil,
            port: 22,
            identityFiles: [],
            proxyJump: "bastion",
            proxyCommand: "ssh bastion nc %h %p"
        )

        let draft = ProcessSSHConfigResolver.makeDraft(from: resolved)

        XCTAssertEqual(draft.authType, .password)
        XCTAssertEqual(draft.unsupportedOptions.map(\.key), ["proxyjump", "proxycommand"])
    }
}

