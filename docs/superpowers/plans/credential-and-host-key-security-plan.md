# Credential and Host Key Security Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the module-level security foundation for Keychain-backed SSH credentials and wetrans-managed trusted host keys.

**Architecture:** Keep secrets behind `CredentialStore`, host-key records behind `TrustedHostStore`, and verification decisions in a pure `HostKeyVerificationPolicy`. Production Keychain code stays isolated in `wetrans/Security`, file-backed trust persistence reuses `JSONDocumentStore`, and UI/connection code consumes only protocols and decisions.

**Tech Stack:** Swift, SwiftPM, XCTest, Security.framework Keychain Services, JSON persistence.

---

## Source Spec

- `docs/superpowers/specs/credential-and-host-key-security-spec.md`
- `docs/data-model.md`
- `docs/architecture-design.md`

## File Map

Create or modify:

```text
wetrans/Security/CredentialStore.swift
wetrans/Security/KeychainCredentialStore.swift
wetrans/Security/TrustedHostStore.swift
wetrans/Security/FileTrustedHostStore.swift
wetrans/Security/HostKeyVerificationPolicy.swift
wetransTests/Security/KeychainCredentialStoreTests.swift
wetransTests/Security/FileTrustedHostStoreTests.swift
wetransTests/Security/HostKeyVerificationPolicyTests.swift
```

## Task 1: Add KeychainCredentialStore

**Files:**

- Modify: `wetrans/Security/CredentialStore.swift`
- Create: `wetrans/Security/KeychainCredentialStore.swift`
- Test: `wetransTests/Security/KeychainCredentialStoreTests.swift`

- [x] **Step 1: Write failing Keychain tests**

Create `wetransTests/Security/KeychainCredentialStoreTests.swift`:

```swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter KeychainCredentialStoreTests
```

Expected: FAIL because `KeychainCredentialStore` is missing.

- [x] **Step 3: Implement KeychainCredentialStore**

Create `wetrans/Security/KeychainCredentialStore.swift`:

```swift
import Foundation
import Security

public final class KeychainCredentialStore: CredentialStore {
    private let passwordService: String
    private let keyPassphraseService: String

    public init(
        passwordService: String = "wetrans.ssh.password",
        keyPassphraseService: String = "wetrans.ssh.keyPassphrase"
    ) {
        self.passwordService = passwordService
        self.keyPassphraseService = keyPassphraseService
    }

    public func savePassword(_ password: String, hostId: UUID) throws {
        try save(password, service: passwordService, hostId: hostId, operation: "savePassword")
    }

    public func loadPassword(hostId: UUID) throws -> String? {
        try load(service: passwordService, hostId: hostId, operation: "loadPassword")
    }

    public func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws {
        try save(passphrase, service: keyPassphraseService, hostId: hostId, operation: "saveKeyPassphrase")
    }

    public func loadKeyPassphrase(hostId: UUID) throws -> String? {
        try load(service: keyPassphraseService, hostId: hostId, operation: "loadKeyPassphrase")
    }

    public func deleteCredentials(hostId: UUID) throws {
        try delete(service: passwordService, hostId: hostId, operation: "deletePassword")
        try delete(service: keyPassphraseService, hostId: hostId, operation: "deleteKeyPassphrase")
    }

    private func save(_ value: String, service: String, hostId: UUID, operation: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, hostId: hostId)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: addStatus)
        }
    }

    private func load(service: String, hostId: UUID, operation: String) throws -> String? {
        var query = baseQuery(service: service, hostId: hostId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidStoredData
        }
        return value
    }

    private func delete(service: String, hostId: UUID, operation: String) throws {
        let status = SecItemDelete(baseQuery(service: service, hostId: hostId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: status)
        }
    }

    private func baseQuery(service: String, hostId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId.uuidString
        ]
    }
}
```

Modify `wetrans/Security/CredentialStore.swift`:

```swift
import Foundation
import Security

public enum CredentialStoreError: Error, Equatable {
    case unexpectedStatus(operation: String, status: OSStatus)
    case invalidStoredData
}

public protocol CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws
    func loadPassword(hostId: UUID) throws -> String?
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws
    func loadKeyPassphrase(hostId: UUID) throws -> String?
    func deleteCredentials(hostId: UUID) throws
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter KeychainCredentialStoreTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Security/CredentialStore.swift wetrans/Security/KeychainCredentialStore.swift wetransTests/Security/KeychainCredentialStoreTests.swift
git commit -m "feat: add keychain credential store"
```

## Task 2: Add FileTrustedHostStore

**Files:**

- Create: `wetrans/Security/TrustedHostStore.swift`
- Create: `wetrans/Security/FileTrustedHostStore.swift`
- Test: `wetransTests/Security/FileTrustedHostStoreTests.swift`

- [x] **Step 1: Write failing trusted-host store tests**

Create `wetransTests/Security/FileTrustedHostStoreTests.swift`:

```swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter FileTrustedHostStoreTests
```

Expected: FAIL because `FileTrustedHostStore` is missing.

- [x] **Step 3: Implement trusted-host store**

Create `wetrans/Security/TrustedHostStore.swift`:

```swift
import Foundation

public protocol TrustedHostStore {
    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey?
    func trust(_ key: TrustedHostKey) throws
    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws
    func deleteKeys(hostId: UUID) throws
}
```

Create `wetrans/Security/FileTrustedHostStore.swift`:

```swift
import Foundation

public final class FileTrustedHostStore: TrustedHostStore {
    private let store: JSONDocumentStore<TrustedHostKeysDocument>

    public init(store: JSONDocumentStore<TrustedHostKeysDocument>) {
        self.store = store
    }

    public convenience init(applicationSupportDirectory: URL) {
        self.init(
            store: JSONDocumentStore(
                url: applicationSupportDirectory.appendingPathComponent("known_hosts.json")
            )
        )
    }

    public func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey? {
        try loadDocument().trustedHostKeys.first {
            $0.hostId == hostId && $0.hostname == hostname && $0.port == port
        }
    }

    public func trust(_ key: TrustedHostKey) throws {
        var document = try loadDocument()
        document.trustedHostKeys.removeAll {
            $0.hostId == key.hostId && $0.hostname == key.hostname && $0.port == key.port
        }
        document.trustedHostKeys.append(key)
        try store.save(document)
    }

    public func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws {
        var document = try loadDocument()
        guard let index = document.trustedHostKeys.firstIndex(where: {
            $0.hostId == hostId && $0.hostname == hostname && $0.port == port
        }) else {
            return
        }
        document.trustedHostKeys[index].lastVerifiedAt = date
        try store.save(document)
    }

    public func deleteKeys(hostId: UUID) throws {
        var document = try loadDocument()
        document.trustedHostKeys.removeAll { $0.hostId == hostId }
        try store.save(document)
    }

    private func loadDocument() throws -> TrustedHostKeysDocument {
        let document = try store.load(default: TrustedHostKeysDocument())
        guard document.schemaVersion == 1 else {
            throw JSONDocumentStoreError.unsupportedSchemaVersion(document.schemaVersion)
        }
        return document
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter FileTrustedHostStoreTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Security/TrustedHostStore.swift wetrans/Security/FileTrustedHostStore.swift wetransTests/Security/FileTrustedHostStoreTests.swift
git commit -m "feat: add trusted host store"
```

## Task 3: Add HostKeyVerificationPolicy

**Files:**

- Create: `wetrans/Security/HostKeyVerificationPolicy.swift`
- Test: `wetransTests/Security/HostKeyVerificationPolicyTests.swift`

- [x] **Step 1: Write failing policy tests**

Create `wetransTests/Security/HostKeyVerificationPolicyTests.swift`:

```swift
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
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter HostKeyVerificationPolicyTests
```

Expected: FAIL because `HostKeyVerificationPolicy` is missing.

- [x] **Step 3: Implement policy**

Create `wetrans/Security/HostKeyVerificationPolicy.swift`:

```swift
import Foundation

public enum HostKeyVerificationDecision: Equatable {
    case trusted(TrustedHostKey)
    case requiresTrust(candidate: TrustedHostKey)
    case blockedChangedKey(expected: TrustedHostKey, actual: TrustedHostKey)
}

public enum HostKeyVerificationPolicy {
    public static func decide(
        trusted: TrustedHostKey?,
        candidate: TrustedHostKey
    ) -> HostKeyVerificationDecision {
        guard let trusted else {
            return .requiresTrust(candidate: candidate)
        }
        guard trusted.keyType == candidate.keyType,
              trusted.fingerprintSHA256 == candidate.fingerprintSHA256 else {
            return .blockedChangedKey(expected: trusted, actual: candidate)
        }
        return .trusted(trusted)
    }
}
```

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter HostKeyVerificationPolicyTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Security/HostKeyVerificationPolicy.swift wetransTests/Security/HostKeyVerificationPolicyTests.swift
git commit -m "feat: add host key verification policy"
```

## Task 4: Final Verification

**Files:**

- Verify all files changed by this plan.

- [x] **Step 1: Run all tests**

Run:

```bash
swift test
```

Expected: PASS.

- [x] **Step 2: Run build**

Run:

```bash
swift build
```

Expected: PASS.

- [x] **Step 3: Scan for accidental secret fixtures**

Run:

```bash
rg -n 'password|passphrase|secret|phrase' wetrans docs/superpowers/specs/credential-and-host-key-security-spec.md
```

Expected: matches only type names, service names, test placeholder values, and spec language. No real credentials.

- [x] **Step 4: Mark plan complete and commit**

```bash
git status --short
git add docs/superpowers/plans/credential-and-host-key-security-plan.md
git commit -m "docs: mark credential security plan complete"
```

Expected: commit only the plan progress update after verification passes.

## Self-Review Notes

Spec coverage:

- Keychain credentials: Task 1.
- Trusted host key persistence: Task 2.
- Host-key decision policy: Task 3.
- Final verification and secret scan: Task 4.

Out-of-scope items remain intentionally untouched:

- SFTP handshake.
- UI prompts.
- OpenSSH `known_hosts` integration.
- Fingerprint extraction from raw server keys.

