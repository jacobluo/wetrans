import XCTest
@testable import wetrans

final class FileTrustedHostStoreTests: XCTestCase {
    func testMissingFileLoadsAsEmpty() throws {
        let store = makeStore()

        XCTAssertNil(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22))
    }

    func testTrustPersistsAndLookupRequiresHostHostnameAndPort() throws {
        let store = makeStore()
        let key = trustedKey(fingerprint: "SHA256:one")

        try store.trust(key)

        XCTAssertEqual(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22), key)
        XCTAssertNil(try store.lookup(hostId: UUID(), hostname: "dev.example.com", port: 22))
        XCTAssertNil(try store.lookup(hostId: hostId, hostname: "prod.example.com", port: 22))
        XCTAssertNil(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 2222))
    }

    func testTrustingSameHostReplacesRecord() throws {
        let store = makeStore()
        try store.trust(trustedKey(fingerprint: "SHA256:one"))
        let replacement = trustedKey(fingerprint: "SHA256:two")

        try store.trust(replacement)

        XCTAssertEqual(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22), replacement)
    }

    func testRecordVerificationUpdatesLastVerifiedAt() throws {
        let store = makeStore()
        try store.trust(trustedKey(fingerprint: "SHA256:one"))
        let verifiedAt = Date(timeIntervalSince1970: 400)

        try store.recordVerification(hostId: hostId, hostname: "dev.example.com", port: 22, at: verifiedAt)

        XCTAssertEqual(
            try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22)?.lastVerifiedAt,
            verifiedAt
        )
    }

    func testDeleteKeysRemovesRecordsForHost() throws {
        let store = makeStore()
        try store.trust(trustedKey(fingerprint: "SHA256:one"))

        try store.deleteKeys(hostId: hostId)

        XCTAssertNil(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22))
    }

    func testUnsupportedSchemaVersionFails() throws {
        let url = temporaryDirectory().appendingPathComponent("known_hosts.json")
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try #"{"schemaVersion":999,"trustedHostKeys":[]}"#.data(using: .utf8)!.write(to: url)
        let store = FileTrustedHostStore(store: JSONDocumentStore(url: url))

        XCTAssertThrowsError(try store.lookup(hostId: hostId, hostname: "dev.example.com", port: 22)) { error in
            XCTAssertEqual(error as? JSONDocumentStoreError, .unsupportedSchemaVersion(999))
        }
    }

    private let hostId = UUID(uuidString: "00000000-0000-0000-0000-000000000201")!

    private func makeStore() -> FileTrustedHostStore {
        FileTrustedHostStore(applicationSupportDirectory: temporaryDirectory())
    }

    private func trustedKey(fingerprint: String) -> TrustedHostKey {
        TrustedHostKey(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000202")!,
            hostId: hostId,
            hostname: "dev.example.com",
            port: 22,
            keyType: "ssh-ed25519",
            fingerprintSHA256: fingerprint,
            firstTrustedAt: Date(timeIntervalSince1970: 100),
            lastVerifiedAt: Date(timeIntervalSince1970: 100)
        )
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wetrans-tests")
            .appendingPathComponent(UUID().uuidString)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

