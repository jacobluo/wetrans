# SFTP libssh2 Adapter Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a testable libssh2 runtime/probe boundary and a `RemoteFileSystem` adapter skeleton.

**Architecture:** Use dynamic loading so normal tests do not require libssh2 to be installed or linked. Keep libssh2 initialization behind `LibSSH2Runtime`, and make `LibSSH2RemoteFileSystem` explicitly unsupported for real SFTP operations until the next adapter slice.

**Tech Stack:** Swift, SwiftPM, XCTest, Darwin `dlopen`/`dlsym`/`dlclose`.

---

## Source Spec

- `docs/superpowers/specs/sftp-libssh2-adapter-spec.md`
- `docs/superpowers/specs/remote-filesystem-foundation-spec.md`
- `docs/technical-selection.md`

## File Map

Create or modify:

```text
wetrans/RemoteFileSystem/LibSSH2Runtime.swift
wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift
wetransTests/RemoteFileSystem/LibSSH2RuntimeTests.swift
wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift
docs/technical-selection.md
```

## Task 1: Implement LibSSH2 Runtime Probe

**Files:**

- Create: `wetrans/RemoteFileSystem/LibSSH2Runtime.swift`
- Test: `wetransTests/RemoteFileSystem/LibSSH2RuntimeTests.swift`

- [x] **Step 1: Write failing runtime tests**

Tests must cover:

```swift
XCTAssertEqual(paths.first, "/tmp/libssh2.dylib")
XCTAssertEqual(try runtime.initialize(), LibSSH2LibraryInfo(path: "/fake/libssh2.dylib", version: "1.11.1"))
XCTAssertEqual(loader.loadedLibraries[0].initializeCount, 1)
XCTAssertEqual(loader.loadedLibraries[0].shutdownCount, 1)
XCTAssertThrowsError(try runtime.initialize())
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter LibSSH2RuntimeTests
```

Expected: FAIL because libssh2 runtime types are missing.

- [x] **Step 3: Implement runtime, fakeable loader, and Darwin loader**

Implement:

```swift
public struct LibSSH2LibraryInfo: Equatable
public enum LibSSH2Error: Error, Equatable
public protocol LibSSH2LibraryLoading
public final class LibSSH2Runtime
public final class DarwinLibSSH2LibraryLoader
```

Runtime behavior:

- candidate paths put `WETRANS_LIBSSH2_DYLIB` first when present.
- initialize loads and initializes once.
- shutdown calls loaded library shutdown at most once.
- missing library throws `.libraryNotFound(candidates)`.

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter LibSSH2RuntimeTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/LibSSH2Runtime.swift wetransTests/RemoteFileSystem/LibSSH2RuntimeTests.swift docs/superpowers/plans/sftp-libssh2-adapter-plan.md
git commit -m "feat: add libssh2 runtime probe"
```

## Task 2: Implement LibSSH2RemoteFileSystem Skeleton

**Files:**

- Create: `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`
- Test: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`

- [x] **Step 1: Write failing adapter tests**

Tests must cover:

```swift
XCTAssertThrowsError(try await adapter.connect(spec))
XCTAssertEqual(runtime.initializeCallCount, 1)
XCTAssertThrowsError(try await adapter.listDirectory("/", in: session))
await adapter.disconnect(session)
XCTAssertEqual(runtime.shutdownCallCount, 1)
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter LibSSH2RemoteFileSystemTests
```

Expected: FAIL because adapter is missing.

- [x] **Step 3: Implement adapter skeleton**

Implement:

```swift
public final class LibSSH2RemoteFileSystem: RemoteFileSystem {
    public func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    public func disconnect(_ session: RemoteSession) async
    public func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
}
```

Behavior:

- `connect` initializes runtime then throws `LibSSH2Error.operationUnsupported`.
- `listDirectory` throws `RemoteFileSystemError.disconnected`.
- `disconnect` calls runtime shutdown.

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter LibSSH2RemoteFileSystemTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift docs/superpowers/plans/sftp-libssh2-adapter-plan.md
git commit -m "feat: add libssh2 remote filesystem skeleton"
```

## Task 3: Document Dynamic Probe Decision

**Files:**

- Modify: `docs/technical-selection.md`

- [ ] **Step 1: Update technical selection**

Add to SFTP Library section:

```markdown
### Spike Step: Dynamic libssh2 Probe

The first implementation step uses a dynamic libssh2 probe instead of hard-linking the app to a Homebrew path. This keeps normal SwiftPM tests portable while allowing development machines to opt into a real probe through `WETRANS_LIBSSH2_DYLIB` or common Homebrew candidate paths.
```

- [ ] **Step 2: Review diff**

```bash
git diff -- docs/technical-selection.md
```

Expected: only the dynamic probe note is added.

- [ ] **Step 3: Commit**

```bash
git add docs/technical-selection.md docs/superpowers/plans/sftp-libssh2-adapter-plan.md
git commit -m "docs: document libssh2 probe strategy"
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

- [ ] **Step 3: Optional real probe command**

```bash
WETRANS_RUN_LIBSSH2_REAL_PROBE=1 swift test --filter LibSSH2RuntimeRealProbeTests
```

Expected: PASS only on machines with a loadable libssh2. If the test target does not include a real-probe test yet, record that the optional real probe remains future work.

- [ ] **Step 4: Mark plan complete and commit**

```bash
git add docs/superpowers/plans/sftp-libssh2-adapter-plan.md
git commit -m "docs: mark libssh2 adapter plan complete"
```

## Self-Review Notes

Spec coverage:

- Dynamic probe and candidate paths: Task 1.
- Runtime init/shutdown boundary: Task 1.
- `RemoteFileSystem` adapter skeleton: Task 2.
- Technical selection note: Task 3.
- Verification: Task 4.

Out-of-scope items intentionally untouched:

- Real socket connection.
- SSH authentication.
- Host-key extraction.
- SFTP directory listing.
- Upload/download/cancel.
