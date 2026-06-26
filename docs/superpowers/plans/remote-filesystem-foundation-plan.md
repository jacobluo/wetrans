# Remote File System Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement the testable local/remote file-system foundation that future browsing UI and SFTP adapters will consume.

**Architecture:** Keep file browsing behind protocols: `LocalFileSystem` for local directory reads and `RemoteFileSystem` for remote session/list operations. `HostSessionManager` owns per-host runtime state, builds `ConnectionSpec` from saved hosts and credentials, and connects on demand without knowing libssh2 details.

**Tech Stack:** Swift, SwiftPM, XCTest, Foundation `FileManager`, Swift concurrency.

---

## Source Spec

- `docs/superpowers/specs/remote-filesystem-foundation-spec.md`
- `docs/data-model.md`
- `docs/architecture-design.md`

## File Map

Create:

```text
wetrans/FileSystem/LocalFileSystem.swift
wetrans/FileSystem/FileManagerLocalFileSystem.swift
wetrans/RemoteFileSystem/ConnectionSpec.swift
wetrans/RemoteFileSystem/RemoteFileSystem.swift
wetrans/RemoteFileSystem/MockRemoteFileSystem.swift
wetrans/RemoteFileSystem/HostSessionManager.swift
wetransTests/FileSystem/FileManagerLocalFileSystemTests.swift
wetransTests/RemoteFileSystem/ConnectionSpecTests.swift
wetransTests/RemoteFileSystem/HostSessionManagerTests.swift
```

## Task 1: Implement LocalFileSystem

**Files:**

- Create: `wetrans/FileSystem/LocalFileSystem.swift`
- Create: `wetrans/FileSystem/FileManagerLocalFileSystem.swift`
- Test: `wetransTests/FileSystem/FileManagerLocalFileSystemTests.swift`

- [x] **Step 1: Write failing local file-system tests**

Create tests that:

```swift
XCTAssertEqual(items.map(\.name), ["folder", "file.txt"])
XCTAssertTrue(items[0].isDirectory)
XCTAssertEqual(items[1].size, 5)
XCTAssertThrowsError(try fileSystem.listDirectory(fileURL.path))
```

- [x] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter FileManagerLocalFileSystemTests
```

Expected: FAIL because local file-system types are missing.

- [x] **Step 3: Implement local file-system adapter**

Implement:

```swift
public protocol LocalFileSystem {
    func listDirectory(_ path: String) throws -> [FileItem]
}

public enum LocalFileSystemError: Error, Equatable {
    case notDirectory(String)
    case cannotRead(String)
}

public final class FileManagerLocalFileSystem: LocalFileSystem {
    public init(fileManager: FileManager = .default)
    public func listDirectory(_ path: String) throws -> [FileItem]
}
```

Sort directories first, then localized case-insensitive name.

- [x] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter FileManagerLocalFileSystemTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/FileSystem wetransTests/FileSystem docs/superpowers/plans/remote-filesystem-foundation-plan.md
git commit -m "feat: add local file system adapter"
```

## Task 2: Implement RemoteFileSystem Contracts and ConnectionSpec

**Files:**

- Create: `wetrans/RemoteFileSystem/ConnectionSpec.swift`
- Create: `wetrans/RemoteFileSystem/RemoteFileSystem.swift`
- Create: `wetrans/RemoteFileSystem/MockRemoteFileSystem.swift`
- Test: `wetransTests/RemoteFileSystem/ConnectionSpecTests.swift`

- [ ] **Step 1: Write failing connection spec tests**

Create tests that cover:

```swift
XCTAssertEqual(spec.auth, .password("secret"))
XCTAssertEqual(spec.auth, .password(nil))
XCTAssertEqual(spec.auth, .sshKey(identityFile: "~/.ssh/id_ed25519", passphrase: "phrase"))
XCTAssertThrowsError(try ConnectionSpec.make(host: missingIdentityHost, credentialStore: credentials))
XCTAssertEqual(spec.defaultRemotePath, "/last")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter ConnectionSpecTests
```

Expected: FAIL because remote file-system contracts are missing.

- [ ] **Step 3: Implement contracts and mock remote**

Implement:

```swift
public enum ConnectionAuth: Equatable {
    case password(String?)
    case sshKey(identityFile: String, passphrase: String?)
}

public struct ConnectionSpec: Equatable {
    public static func make(host: SavedHost, credentialStore: CredentialStore) throws -> ConnectionSpec
}

public struct RemoteSession: Identifiable, Equatable
public protocol RemoteFileSystem
public final class MockRemoteFileSystem: RemoteFileSystem
```

Use remote path default order: `lastRemotePath`, `defaultRemotePath`, `~`.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter ConnectionSpecTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem wetransTests/RemoteFileSystem docs/superpowers/plans/remote-filesystem-foundation-plan.md
git commit -m "feat: add remote filesystem contracts"
```

## Task 3: Implement HostSessionManager

**Files:**

- Create: `wetrans/RemoteFileSystem/HostSessionManager.swift`
- Test: `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`

- [ ] **Step 1: Write failing session manager tests**

Create tests that verify:

```swift
let items = try await manager.listRemoteDirectory(for: host)
XCTAssertEqual(remoteFileSystem.connectCalls.count, 1)
XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project"])
XCTAssertEqual(manager.state(for: dev).currentRemotePath, "/project")
XCTAssertEqual(manager.state(for: prod).currentRemotePath, "/var/www")
```

- [ ] **Step 2: Run test to verify it fails**

Run:

```bash
swift test --filter HostSessionManagerTests
```

Expected: FAIL because `HostSessionManager` is missing.

- [ ] **Step 3: Implement HostSessionManager**

Implement:

```swift
public final class HostSessionManager {
    public func state(for host: SavedHost) -> HostSessionState
    public func updateLocalPath(_ path: String, for host: SavedHost)
    public func updateRemotePath(_ path: String, for host: SavedHost)
    public func listRemoteDirectory(for host: SavedHost) async throws -> [FileItem]
    public func disconnect(hostId: UUID) async
}
```

Store sessions by host ID and reuse live sessions for repeated listings.

- [ ] **Step 4: Run test to verify it passes**

Run:

```bash
swift test --filter HostSessionManagerTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/HostSessionManager.swift wetransTests/RemoteFileSystem/HostSessionManagerTests.swift docs/superpowers/plans/remote-filesystem-foundation-plan.md
git commit -m "feat: add host session manager"
```

## Task 4: Final Verification

**Files:**

- Verify all files changed by this plan.

- [ ] **Step 1: Run all tests**

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run build**

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Confirm no recursive remote scanning was introduced**

```bash
rg -n 'recursive|enumerator|subpaths|contentsOfDirectory' wetrans/RemoteFileSystem wetrans/FileSystem
```

Expected: `contentsOfDirectory` appears only in `FileManagerLocalFileSystem`; no recursive remote traversal exists.

- [ ] **Step 4: Mark plan complete and commit**

```bash
git add docs/superpowers/plans/remote-filesystem-foundation-plan.md
git commit -m "docs: mark remote filesystem plan complete"
```

## Self-Review Notes

Spec coverage:

- Local listing: Task 1.
- Connection spec and remote contracts: Task 2.
- Per-host runtime state and connect-on-demand: Task 3.
- Build/test/no-recursive-scan verification: Task 4.

Out-of-scope items intentionally untouched:

- Real libssh2 adapter.
- AppKit panels.
- Upload/download.
- Transfer queue.

