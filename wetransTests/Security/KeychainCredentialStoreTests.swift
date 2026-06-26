import XCTest
@testable import wetrans

final class KeychainCredentialStoreTests: XCTestCase {
    private let hostId = UUID(uuidString: "00000000-0000-0000-0000-000000000101")!
    private var store: KeychainCredentialStore!

    override func setUpWithError() throws {
        try super.setUpWithError()
        store = KeychainCredentialStore(
            passwordService: "wetrans.tests.ssh.password",
            keyPassphraseService: "wetrans.tests.ssh.keyPassphrase"
        )
        try store.deleteCredentials(hostId: hostId)
    }

    override func tearDownWithError() throws {
        try store.deleteCredentials(hostId: hostId)
        store = nil
        try super.tearDownWithError()
    }

    func testSavingAndLoadingPasswordRoundTrips() throws {
        try store.savePassword("secret", hostId: hostId)

        XCTAssertEqual(try store.loadPassword(hostId: hostId), "secret")
    }

    func testSavingPasswordTwiceUpdatesValue() throws {
        try store.savePassword("first", hostId: hostId)
        try store.savePassword("second", hostId: hostId)

        XCTAssertEqual(try store.loadPassword(hostId: hostId), "second")
    }

    func testSavingAndLoadingKeyPassphraseRoundTrips() throws {
        try store.saveKeyPassphrase("phrase", hostId: hostId)

        XCTAssertEqual(try store.loadKeyPassphrase(hostId: hostId), "phrase")
    }

    func testLoadingMissingCredentialsReturnsNil() throws {
        XCTAssertNil(try store.loadPassword(hostId: hostId))
        XCTAssertNil(try store.loadKeyPassphrase(hostId: hostId))
    }

    func testDeletingCredentialsRemovesBothItems() throws {
        try store.savePassword("secret", hostId: hostId)
        try store.saveKeyPassphrase("phrase", hostId: hostId)

        try store.deleteCredentials(hostId: hostId)

        XCTAssertNil(try store.loadPassword(hostId: hostId))
        XCTAssertNil(try store.loadKeyPassphrase(hostId: hostId))
    }
}

