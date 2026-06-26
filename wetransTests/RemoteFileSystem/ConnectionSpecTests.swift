import XCTest
@testable import wetrans

final class ConnectionSpecTests: XCTestCase {
    func testPasswordHostIncludesPasswordFromCredentialStore() throws {
        let host = SavedHost.fixture(authType: .password)
        let credentials = InMemoryCredentialStore()
        try credentials.savePassword("secret", hostId: host.id)

        let spec = try ConnectionSpec.make(host: host, credentialStore: credentials)

        XCTAssertEqual(spec.auth, .password("secret"))
        XCTAssertEqual(spec.defaultRemotePath, "~")
    }

    func testPasswordHostAllowsMissingPassword() throws {
        let host = SavedHost.fixture(authType: .password)

        let spec = try ConnectionSpec.make(host: host, credentialStore: InMemoryCredentialStore())

        XCTAssertEqual(spec.auth, .password(nil))
    }

    func testSSHKeyHostIncludesIdentityFileAndPassphrase() throws {
        let host = SavedHost.fixture(authType: .sshKey, identityFile: "~/.ssh/id_ed25519")
        let credentials = InMemoryCredentialStore()
        try credentials.saveKeyPassphrase("phrase", hostId: host.id)

        let spec = try ConnectionSpec.make(host: host, credentialStore: credentials)

        XCTAssertEqual(spec.auth, .sshKey(identityFile: "~/.ssh/id_ed25519", passphrase: "phrase"))
    }

    func testSSHKeyHostWithoutIdentityFileThrows() {
        let host = SavedHost.fixture(authType: .sshKey, identityFile: nil)

        XCTAssertThrowsError(try ConnectionSpec.make(host: host, credentialStore: InMemoryCredentialStore())) { error in
            XCTAssertEqual(error as? ConnectionSpecError, .missingIdentityFile(hostId: host.id))
        }
    }

    func testRemotePathDefaultsToLastThenDefaultThenTilde() throws {
        let lastPathHost = SavedHost.fixture(authType: .password, lastRemotePath: "/last", defaultRemotePath: "/default")
        let defaultPathHost = SavedHost.fixture(authType: .password, defaultRemotePath: "/default")
        let fallbackHost = SavedHost.fixture(authType: .password)

        XCTAssertEqual(try ConnectionSpec.make(host: lastPathHost, credentialStore: InMemoryCredentialStore()).defaultRemotePath, "/last")
        XCTAssertEqual(try ConnectionSpec.make(host: defaultPathHost, credentialStore: InMemoryCredentialStore()).defaultRemotePath, "/default")
        XCTAssertEqual(try ConnectionSpec.make(host: fallbackHost, credentialStore: InMemoryCredentialStore()).defaultRemotePath, "~")
    }
}

private extension SavedHost {
    static func fixture(
        id: UUID = UUID(),
        authType: AuthType,
        identityFile: String? = nil,
        lastRemotePath: String? = nil,
        defaultRemotePath: String? = nil
    ) -> SavedHost {
        SavedHost(
            id: id,
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: authType,
            identityFile: identityFile,
            lastRemotePath: lastRemotePath,
            defaultRemotePath: defaultRemotePath
        )
    }
}

