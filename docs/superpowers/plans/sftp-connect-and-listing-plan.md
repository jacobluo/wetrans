# SFTP Connect and Listing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the libssh2 placeholder adapter with a testable real-connect/listing foundation.

**Architecture:** Keep `RemoteFileSystem` stable. Add a fakeable `LibSSH2Client` boundary so adapter behavior is unit-tested without a real server, and keep raw socket/libssh2 symbol work inside `LibSSH2DynamicClient`.

**Tech Stack:** Swift, SwiftPM, XCTest, Darwin sockets, dynamic libssh2 symbols.

---

## Source Spec

- `docs/superpowers/specs/sftp-connect-and-listing-spec.md`
- `docs/superpowers/specs/sftp-libssh2-adapter-spec.md`
- `docs/architecture-design.md`
- `docs/technical-selection.md`

## File Map

Create or modify:

```text
wetrans/RemoteFileSystem/RemoteFileSystem.swift
wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift
wetrans/RemoteFileSystem/LibSSH2Client.swift
wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift
wetrans/RemoteFileSystem/LibSSH2Path.swift
wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift
wetransTests/RemoteFileSystem/LibSSH2DynamicClientTests.swift
docs/technical-selection.md
```

## Task 1: Adapter Behavior and Host-Key Decisions

**Files:**

- Modify: `wetrans/RemoteFileSystem/RemoteFileSystem.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`
- Create: `wetrans/RemoteFileSystem/LibSSH2Client.swift`
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`

- [x] **Step 1: Write failing adapter tests**

Tests must cover:

```swift
let adapter = LibSSH2RemoteFileSystem(
    runtime: runtime,
    trustedHostStore: trustedStore,
    clientFactory: factory
)
let session = try await adapter.connect(spec)
XCTAssertEqual(runtime.initializeCallCount, 1)
XCTAssertEqual(factory.clients[0].connectCalls, [spec])
XCTAssertEqual(factory.clients[0].authenticateCalls, [spec.auth])
XCTAssertEqual(factory.clients[0].openSFTPCallCount, 1)
XCTAssertEqual(session.hostId, spec.hostId)
```

Also test:

```swift
XCTAssertThrowsError(try await adapter.connect(spec)) { error in
    XCTAssertEqual(error as? RemoteFileSystemError, .hostKeyRequiresTrust(candidate))
}
XCTAssertThrowsError(try await adapter.connect(spec)) { error in
    XCTAssertEqual(error as? RemoteFileSystemError, .hostKeyChanged(expected: trusted, actual: changed))
}
XCTAssertEqual(try await adapter.listDirectory("/var/log", in: session), items)
await adapter.disconnect(session)
XCTAssertEqual(factory.clients[0].disconnectCallCount, 1)
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter LibSSH2RemoteFileSystemTests
```

Expected: FAIL because host-key errors and client factory types are missing.

- [x] **Step 3: Implement adapter boundary**

Implement:

```swift
public struct LibSSH2HostKey: Equatable
public protocol LibSSH2Client
public protocol LibSSH2ClientFactory
public final class DefaultLibSSH2ClientFactory
```

Update `RemoteFileSystemError`:

```swift
case hostKeyRequiresTrust(TrustedHostKey)
case hostKeyChanged(expected: TrustedHostKey, actual: TrustedHostKey)
```

Update `LibSSH2RemoteFileSystem`:

- Store `[UUID: LibSSH2Client]`.
- Initialize runtime in `connect`.
- Create a client through the factory.
- Connect, fetch host key, verify through `TrustedHostStore`.
- Authenticate and open SFTP only after host-key trust passes.
- Delegate listing by session id.
- Disconnect and remove clients.

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter LibSSH2RemoteFileSystemTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/RemoteFileSystem.swift wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift wetrans/RemoteFileSystem/LibSSH2Client.swift wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift docs/superpowers/plans/sftp-connect-and-listing-plan.md
git commit -m "feat: add sftp adapter session boundary"
```

## Task 2: Directory Path and Metadata Mapping

**Files:**

- Create: `wetrans/RemoteFileSystem/LibSSH2Path.swift`
- Create: `wetransTests/RemoteFileSystem/LibSSH2DynamicClientTests.swift`

- [ ] **Step 1: Write failing path and metadata tests**

Tests must cover:

```swift
XCTAssertEqual(LibSSH2Path.join(directory: "/var/log", name: "app.log"), "/var/log/app.log")
XCTAssertEqual(LibSSH2Path.join(directory: "/", name: "etc"), "/etc")
XCTAssertEqual(LibSSH2Path.join(directory: "relative", name: "file"), "relative/file")
XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o040755), "drwxr-xr-x")
XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o100644), "-rw-r--r--")
XCTAssertTrue(LibSSH2Path.isDirectory(permissions: 0o040755))
XCTAssertFalse(LibSSH2Path.isDirectory(permissions: 0o100644))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter LibSSH2DynamicClientTests
```

Expected: FAIL because `LibSSH2Path` is missing.

- [ ] **Step 3: Implement mapping helpers**

Implement `LibSSH2Path`:

- `join(directory:name:)`
- `isDirectory(permissions:)`
- `isSymlink(permissions:)`
- `permissionsText(from:)`

- [ ] **Step 4: Run test to verify it passes**

```bash
swift test --filter LibSSH2DynamicClientTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/LibSSH2Path.swift wetransTests/RemoteFileSystem/LibSSH2DynamicClientTests.swift docs/superpowers/plans/sftp-connect-and-listing-plan.md
git commit -m "feat: add sftp directory metadata mapping"
```

## Task 3: Dynamic libssh2 Client

**Files:**

- Create: `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2Client.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2Runtime.swift`
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RuntimeTests.swift`

- [ ] **Step 1: Write failing runtime symbol-provider tests**

Tests must prove a loaded library can provide symbols through a protocol:

```swift
XCTAssertNil(fake.symbol(named: "missing"))
XCTAssertNotNil(fake.symbol(named: "present"))
```

- [ ] **Step 2: Run test to verify it fails**

```bash
swift test --filter LibSSH2RuntimeTests
```

Expected: FAIL because symbol lookup is not exposed.

- [ ] **Step 3: Implement dynamic client**

Implement:

- `LibSSH2SymbolProviding`
- `LibSSH2RuntimeManaging.loadedSymbolProvider()`
- `LibSSH2DynamicClient`

The dynamic client must:

- Open a TCP socket with `getaddrinfo` and `connect`.
- Resolve libssh2 symbols from the loaded dylib.
- Call session init, blocking mode, handshake, hostkey, auth, SFTP init.
- List one directory with `libssh2_sftp_opendir_ex` and `libssh2_sftp_readdir_ex`.
- Convert entries to `FileItem`.
- Close SFTP handles, session, and socket in `disconnect`.

- [ ] **Step 4: Run focused tests**

```bash
swift test --filter LibSSH2RuntimeTests
swift test --filter LibSSH2DynamicClientTests
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/LibSSH2Runtime.swift wetrans/RemoteFileSystem/LibSSH2Client.swift wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift wetransTests/RemoteFileSystem/LibSSH2RuntimeTests.swift docs/superpowers/plans/sftp-connect-and-listing-plan.md
git commit -m "feat: add dynamic libssh2 sftp client"
```

## Task 4: Opt-in Integration Test and Documentation

**Files:**

- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Modify: `docs/technical-selection.md`

- [ ] **Step 1: Add skipped-by-default integration test**

Add a test that skips unless:

```text
WETRANS_RUN_SFTP_INTEGRATION=1
WETRANS_SFTP_HOST
WETRANS_SFTP_PORT
WETRANS_SFTP_USER
WETRANS_SFTP_LIST_PATH
```

The test should connect and list the configured path only when environment variables are present.

- [ ] **Step 2: Update technical selection**

Document that this slice adds real connect/listing support behind opt-in integration tests, while upload/download remains future transfer queue work.

- [ ] **Step 3: Run verification**

```bash
swift test
swift build
```

Expected: PASS, with integration skipped unless explicitly enabled.

- [ ] **Step 4: Commit**

```bash
git add wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift docs/technical-selection.md docs/superpowers/plans/sftp-connect-and-listing-plan.md
git commit -m "docs: document sftp connect listing verification"
```

## Task 5: Final Verification

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

- [ ] **Step 3: Review changed files**

```bash
git diff --stat main..HEAD
git status --short
```

Expected: changed files match this plan and working tree is clean.

- [ ] **Step 4: Mark plan complete and commit if needed**

```bash
git add docs/superpowers/plans/sftp-connect-and-listing-plan.md
git commit -m "docs: mark sftp connect listing plan complete"
```

## Self-Review Notes

Out-of-scope items intentionally untouched:

- Upload/download.
- Transfer queue.
- ProxyJump.
- SSH Agent.
- Keyboard-interactive auth.
- UI trust prompt.
