import XCTest
@testable import wetrans

final class HostKeyVerificationPolicyTests: XCTestCase {
    func testUnknownKeyRequiresTrust() {
        let candidate = key(fingerprint: "SHA256:new")

        let decision = HostKeyVerificationPolicy.decide(trusted: nil, candidate: candidate)

        XCTAssertEqual(decision, .requiresTrust(candidate: candidate))
    }

    func testMatchingKeyIsTrusted() {
        let trusted = key(fingerprint: "SHA256:same")
        let candidate = key(fingerprint: "SHA256:same")

        let decision = HostKeyVerificationPolicy.decide(trusted: trusted, candidate: candidate)

        XCTAssertEqual(decision, .trusted(trusted))
    }

    func testChangedFingerprintIsBlocked() {
        let trusted = key(fingerprint: "SHA256:old")
        let candidate = key(fingerprint: "SHA256:new")

        let decision = HostKeyVerificationPolicy.decide(trusted: trusted, candidate: candidate)

        XCTAssertEqual(decision, .blockedChangedKey(expected: trusted, actual: candidate))
    }

    func testChangedKeyTypeIsBlocked() {
        let trusted = key(keyType: "ssh-ed25519", fingerprint: "SHA256:same")
        let candidate = key(keyType: "ssh-rsa", fingerprint: "SHA256:same")

        let decision = HostKeyVerificationPolicy.decide(trusted: trusted, candidate: candidate)

        XCTAssertEqual(decision, .blockedChangedKey(expected: trusted, actual: candidate))
    }

    private func key(keyType: String = "ssh-ed25519", fingerprint: String) -> TrustedHostKey {
        TrustedHostKey(
            id: UUID(uuidString: "00000000-0000-0000-0000-000000000301")!,
            hostId: UUID(uuidString: "00000000-0000-0000-0000-000000000302")!,
            hostname: "dev.example.com",
            port: 22,
            keyType: keyType,
            fingerprintSHA256: fingerprint,
            firstTrustedAt: Date(timeIntervalSince1970: 100),
            lastVerifiedAt: Date(timeIntervalSince1970: 100)
        )
    }
}

