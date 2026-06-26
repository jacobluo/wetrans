# Credential and Host Key Security Spec

Status: Draft for review
Parent PRD: `docs/prd.md`
Related docs:

- `docs/architecture-design.md`
- `docs/data-model.md`
- `docs/implementation-plan.md`
- `docs/superpowers/specs/host-onboarding-and-management-spec.md`

## 1. Purpose

This spec defines the security foundation required before wetrans connects to real SSH/SFTP servers.

It covers two implementation-plan concerns:

- Credential storage through macOS Keychain.
- wetrans-managed SSH host-key trust records.

The feature slice ends when credentials and trusted host keys can be saved, read, deleted, and verified through testable module interfaces. It does not perform a real SSH handshake and does not show final connection UI.

## 2. User Value

Users should be able to save SSH credentials without exposing secrets in local JSON files.

Users should also receive correct trust behavior before remote browsing starts:

- Unknown host key: require explicit trust later in the connection UI.
- Matching host key: allow connection.
- Changed host key: block connection because it may indicate a security risk.

This keeps wetrans safe by default while preserving a clear module boundary for the later SFTP connection spec.

## 3. Scope

### 3.1 In Scope

- `KeychainCredentialStore` implementing the existing `CredentialStore` protocol.
- Keychain save, load, update, and delete for:
  - SSH password.
  - Private key passphrase.
- Keychain service/account naming.
- Keychain error mapping into app-level errors.
- `TrustedHostStore` protocol.
- File-backed `TrustedHostStore` using `known_hosts.json`.
- `TrustedHostKey` lookup by `hostId`, `hostname`, and `port`.
- Trusting a new host key.
- Updating `lastVerifiedAt`.
- Schema version handling for `known_hosts.json`.
- `HostKeyVerificationPolicy`.
- Unit tests for credential behavior, trusted-host persistence, and host-key verification decisions.
- Integration point for host deletion to clean up credentials through `CredentialStore`.

### 3.2 Out of Scope

- Real SSH/SFTP connection.
- Reading host keys from libssh2 or libssh.
- Host-key fingerprint calculation from raw SSH key bytes.
- Unknown-host confirmation UI.
- Changed-host-key warning UI.
- App Sandbox migration.
- Notarization or Developer ID packaging.
- Modifying the user's OpenSSH `known_hosts`.
- Reading the user's OpenSSH `known_hosts`.
- SSH Agent integration.
- ProxyJump or ProxyCommand support.

## 4. Product Decisions

### 4.1 Secrets Live Only in Keychain

`hosts.json` must never contain:

- SSH password.
- Private key passphrase.
- Token-like credential values.

`SavedHost` stores only non-sensitive metadata such as hostname, username, auth type, and identity file path.

### 4.2 Keychain Keys Use Host IDs

Credentials are scoped by stable wetrans host ID, not hostname or SSH Config alias.

```text
service: wetrans.ssh.password
account: <hostId.uuidString>

service: wetrans.ssh.keyPassphrase
account: <hostId.uuidString>
```

This avoids credential collisions when two saved hosts point to the same server with different usernames or auth settings.

### 4.3 wetrans Owns Its Host-Key Trust Store

wetrans stores trusted host keys in:

```text
~/Library/Application Support/wetrans/known_hosts.json
```

It does not mutate OpenSSH `known_hosts`.

This keeps wetrans trust decisions explicit and avoids surprising changes to the user's terminal SSH environment.

### 4.4 Host-Key Verification Is UI-Agnostic

The security module returns a verification decision. It does not show dialogs.

Later connection/UI specs decide how to present `.requiresTrust` and `.blockedChangedKey`.

## 5. Data Model

### 5.1 TrustedHostKey

Use the model already defined in `docs/data-model.md`:

```swift
struct TrustedHostKey: Identifiable, Codable, Equatable {
    let id: UUID
    let hostId: UUID
    var hostname: String
    var port: Int
    var keyType: String
    var fingerprintSHA256: String
    var firstTrustedAt: Date
    var lastVerifiedAt: Date
}
```

### 5.2 known_hosts.json

Document shape:

```json
{
  "schemaVersion": 1,
  "trustedHostKeys": []
}
```

Rules:

- `schemaVersion == 1` is supported.
- Unknown future versions fail with a readable persistence error.
- Writes use `JSONDocumentStore` atomic save behavior.
- Lookups match all of `hostId`, `hostname`, and `port`.

### 5.3 Keychain Items

Password item:

```text
service: wetrans.ssh.password
account: <hostId.uuidString>
value: UTF-8 password bytes
```

Private key passphrase item:

```text
service: wetrans.ssh.keyPassphrase
account: <hostId.uuidString>
value: UTF-8 passphrase bytes
```

Rules:

- Saving a value should create or update the item.
- Loading a missing item returns `nil`.
- Deleting credentials removes both password and passphrase items for the host.
- Keychain errors are mapped to app errors; raw OSStatus codes may be included in debug descriptions but should not be shown directly as the primary user message.

## 6. Module Design

### 6.1 CredentialStore

Existing protocol:

```swift
protocol CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws
    func loadPassword(hostId: UUID) throws -> String?
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws
    func loadKeyPassphrase(hostId: UUID) throws -> String?
    func deleteCredentials(hostId: UUID) throws
}
```

Add production adapter:

```swift
final class KeychainCredentialStore: CredentialStore
```

Responsibilities:

- Translate protocol calls into Keychain Services queries.
- Use stable service names.
- Store UTF-8 data.
- Update existing items.
- Return `nil` for `errSecItemNotFound`.
- Throw `CredentialStoreError` for unexpected failures.

Non-responsibilities:

- Prompting the user.
- Validating SSH auth methods.
- Logging secret values.
- Owning host deletion.

### 6.2 TrustedHostStore

Add protocol:

```swift
protocol TrustedHostStore {
    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey?
    func trust(_ key: TrustedHostKey) throws
    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws
    func deleteKeys(hostId: UUID) throws
}
```

Add file-backed adapter:

```swift
final class FileTrustedHostStore: TrustedHostStore
```

Responsibilities:

- Load and save `TrustedHostKeysDocument`.
- Match trust records by `hostId`, `hostname`, and `port`.
- Insert or replace trust records.
- Update `lastVerifiedAt`.
- Delete all trust records for a deleted host.

Non-responsibilities:

- Calculating fingerprints.
- Asking the user whether to trust a key.
- Connecting to SSH servers.

### 6.3 HostKeyVerificationPolicy

Add a pure policy module:

```swift
enum HostKeyVerificationDecision: Equatable {
    case trusted(TrustedHostKey)
    case requiresTrust(candidate: TrustedHostKey)
    case blockedChangedKey(expected: TrustedHostKey, actual: TrustedHostKey)
}

enum HostKeyVerificationPolicy {
    static func decide(
        trusted: TrustedHostKey?,
        candidate: TrustedHostKey
    ) -> HostKeyVerificationDecision
}
```

Rules:

- If no trusted key exists, return `.requiresTrust(candidate:)`.
- If key type and fingerprint match, return `.trusted(existingKey)`.
- If key type or fingerprint differs, return `.blockedChangedKey(expected:actual:)`.

The policy intentionally ignores UI and persistence. Callers decide whether to call `trust(_:)` or block the connection.

## 7. Data Flow

### 7.1 Saving Credentials From Host Onboarding

```text
ConnectHostViewModel
-> HostDraft.makeSavedHost()
-> HostCatalog.save(host)
-> CredentialStore.savePassword / saveKeyPassphrase
```

Expected outcome:

- Host metadata persists to `hosts.json`.
- Secrets persist to Keychain.
- Secrets do not appear in `SavedHost` or `hosts.json`.

### 7.2 Deleting a Host

```text
Delete host action
-> HostCatalog.delete(hostId)
-> CredentialStore.deleteCredentials(hostId)
-> TrustedHostStore.deleteKeys(hostId)
```

The host-management UI may still wire this sequence later. This spec requires module support and tests for cleanup behavior.

### 7.3 Later Connection Host-Key Check

Future SFTP connection code will follow this shape:

```text
Remote adapter obtains current host key fingerprint
-> build TrustedHostKey candidate
-> TrustedHostStore.lookup(hostId, hostname, port)
-> HostKeyVerificationPolicy.decide(trusted, candidate)
-> caller handles decision
```

This spec implements the store and policy, not the remote adapter.

## 8. Error Handling

### 8.1 CredentialStoreError

Recommended shape:

```swift
enum CredentialStoreError: Error, Equatable {
    case unexpectedStatus(operation: String, status: OSStatus)
    case invalidStoredData
}
```

Rules:

- Missing item is not an error when loading.
- Secret values must never be included in errors.
- Errors should identify the operation, such as `savePassword` or `loadKeyPassphrase`.

### 8.2 TrustedHostStore Errors

Use existing JSON persistence errors where possible.

Additional rules:

- Unknown schema version fails before returning records.
- Missing `known_hosts.json` is treated as an empty trust store.
- Recording verification for a missing trust record is a no-op, matching current `HostCatalog` update behavior for missing hosts.

## 9. Security Requirements

- Do not log passwords or passphrases.
- Do not write passwords or passphrases to fixtures, docs, or JSON snapshots.
- Do not include secret values in thrown errors.
- Do not modify OpenSSH `known_hosts`.
- Treat host-key mismatch as blocking.
- Use `hostId.uuidString` as Keychain account.
- Keep Keychain implementation isolated behind `CredentialStore`.
- Keep trust-store implementation isolated behind `TrustedHostStore`.

## 10. Testing Requirements

### 10.1 Unit Tests

Credential tests:

- Saving and loading password returns the saved value.
- Saving and loading key passphrase returns the saved value.
- Saving twice updates the value.
- Loading a missing credential returns `nil`.
- Deleting credentials removes password and passphrase.
- Keychain errors map to `CredentialStoreError`.

Trusted-host tests:

- Missing `known_hosts.json` loads as empty.
- Trusting a key persists it.
- Lookup requires matching `hostId`, `hostname`, and `port`.
- Trusting the same host again replaces the record.
- `recordVerification` updates `lastVerifiedAt`.
- `deleteKeys(hostId:)` removes trust records for that host.
- Unknown schema version fails.

Policy tests:

- No existing key returns `.requiresTrust`.
- Matching key type and fingerprint returns `.trusted`.
- Changed fingerprint returns `.blockedChangedKey`.
- Changed key type returns `.blockedChangedKey`.

### 10.2 Integration Tests

SwiftPM tests should verify:

```bash
swift test
```

No real system SSH server is required.

Keychain tests must use deterministic test service names and clean them up in teardown:

```text
wetrans.tests.ssh.password
wetrans.tests.ssh.keyPassphrase
```

## 11. Acceptance Criteria

- `KeychainCredentialStore` implements `CredentialStore`.
- Passwords and passphrases can be saved, loaded, updated, and deleted.
- Missing Keychain items load as `nil`.
- `SavedHost` and `hosts.json` still contain no secret fields.
- `TrustedHostStore` persists `TrustedHostKey` records in `known_hosts.json`.
- Unknown host key returns `.requiresTrust`.
- Matching host key returns `.trusted`.
- Changed host key returns `.blockedChangedKey`.
- Deleting a host can delete credentials and trusted host keys through module calls.
- All new behavior has focused tests.
- `swift test` passes.

## 12. Implementation Notes

- Use Security.framework Keychain Services directly from Swift.
- Keep Keychain query construction in a small helper to avoid duplicated dictionaries.
- Keep service names centralized.
- Continue using `JSONDocumentStore` for atomic JSON writes.
- Keep `InMemoryCredentialStore` for tests that do not need real Keychain behavior.
- The later connection spec should depend on `CredentialStore`, `TrustedHostStore`, and `HostKeyVerificationPolicy`, not concrete adapters.

## 13. Future Work

- UI flow for unknown host key confirmation.
- UI flow for changed host key blocking.
- Host-key extraction from libssh2 or libssh.
- Fingerprint calculation from raw SSH public key bytes.
- Developer ID signing and notarization.
- Optional comparison with OpenSSH `known_hosts` after explicit design.
