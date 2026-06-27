# Directory Transfers Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Support directory-level upload and download by recursively expanding selected directories into existing file transfer tasks.

**Architecture:** Keep the queue model unchanged: one file remains one `TransferTask`. Add focused expansion helpers for local and remote directory walking, add an arbitrary-path remote listing method to `HostSessionManager`, and add remote parent-directory creation to upload execution.

**Tech Stack:** Swift, SwiftUI, Swift concurrency, XCTest, libssh2 SFTP.

---

## Task 1: Planning and Documentation

**Files:**
- Create: `docs/superpowers/specs/directory-transfers-spec.md`
- Create: `docs/superpowers/plans/directory-transfers-plan.md`
- Modify: `docs/implementation-plan.md`
- Modify: `docs/prd.md`
- Modify: `docs/internal-test-checklist.md`

- [x] **Step 1: Record the design**

Document that drag-and-drop is no longer near-term scope and directory transfer is the new slice.

- [x] **Step 2: Update product docs**

Remove near-term drag-and-drop references from productization/backlog sections and add directory upload/download.

## Task 2: Remote Parent Directory Creation

**Files:**
- Modify: `wetrans/RemoteFileSystem/RemoteFileSystem.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2Client.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`
- Modify: `wetrans/RemoteFileSystem/MockRemoteFileSystem.swift`
- Modify: `wetrans/TransferQueue/SFTPTransferEngine.swift`
- Test: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Test: `wetransTests/TransferQueue/SFTPTransferEngineTests.swift`

- [x] **Step 1: Write failing adapter and engine tests**

Cover `ensureDirectory` delegation and upload parent directory creation before upload.

- [x] **Step 2: Verify red**

Run:

```bash
swift test --filter LibSSH2RemoteFileSystemTests
swift test --filter SFTPTransferEngineTests
```

Expected: FAIL because directory creation APIs do not exist.

- [x] **Step 3: Implement directory creation boundary**

Add `ensureDirectory` through `RemoteFileSystem`, `LibSSH2Client`, `LibSSH2RemoteFileSystem`, `MockRemoteFileSystem`, and `LibSSH2DynamicClient`.

- [x] **Step 4: Ensure upload parent directory**

Have `SFTPTransferEngine` call `remoteFileSystem.ensureDirectory(BrowserPath.remoteParent(of: task.remotePath), in: session)` before each upload.

- [x] **Step 5: Verify green**

Run:

```bash
swift test --filter LibSSH2RemoteFileSystemTests
swift test --filter SFTPTransferEngineTests
```

Expected: PASS.

## Task 3: Arbitrary Remote Directory Listing

**Files:**
- Modify: `wetrans/RemoteFileSystem/HostSessionManager.swift`
- Test: `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`

- [x] **Step 1: Write failing test**

Cover listing a child remote path without mutating `currentRemotePath`.

- [x] **Step 2: Verify red**

Run: `swift test --filter HostSessionManagerTests`

Expected: FAIL because `listRemoteDirectory(path:for:)` does not exist.

- [x] **Step 3: Implement arbitrary-path listing**

Add `listRemoteDirectory(path:for:)` and reuse stale-session retry behavior.

- [x] **Step 4: Verify green**

Run: `swift test --filter HostSessionManagerTests`

Expected: PASS.

## Task 4: Directory Transfer Planning

**Files:**
- Create: `wetrans/TransferQueue/DirectoryTransferPlanner.swift`
- Test: `wetransTests/TransferQueue/DirectoryTransferPlannerTests.swift`

- [x] **Step 1: Write failing planner tests**

Cover local upload expansion, remote download expansion, mixed file/directory selections, top-level directory preservation, and symlink-directory skipping.

- [x] **Step 2: Verify red**

Run: `swift test --filter DirectoryTransferPlannerTests`

Expected: FAIL because planner does not exist.

- [x] **Step 3: Implement planner**

Use `LocalFileSystem.listDirectory` and `HostSessionManager.listRemoteDirectory(path:for:)` to recursively build file tasks.

- [x] **Step 4: Verify green**

Run: `swift test --filter DirectoryTransferPlannerTests`

Expected: PASS.

## Task 5: Main Browser Integration

**Files:**
- Modify: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Modify: `wetrans/UI/FileBrowsing/MainBrowserView.swift`
- Test: `wetransTests/UI/MainBrowserViewModelTests.swift`

- [x] **Step 1: Write failing view-model tests**

Cover selecting a local directory for upload and selecting a remote directory for download.

- [x] **Step 2: Verify red**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: FAIL because directories are still filtered out.

- [x] **Step 3: Wire planner into enqueue actions**

Use the planner from selection and context actions; enable transfer actions when selected items contain files or directories.

- [x] **Step 4: Verify green**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: PASS.

## Task 6: Final Verification

- [x] **Step 1: Run focused tests**

Run:

```bash
swift test --filter LibSSH2RemoteFileSystemTests
swift test --filter SFTPTransferEngineTests
swift test --filter HostSessionManagerTests
swift test --filter DirectoryTransferPlannerTests
swift test --filter MainBrowserViewModelTests
```

Expected: PASS.

- [x] **Step 2: Run full verification**

Run: `scripts/verify`

Expected: PASS.

- [x] **Step 3: Commit**

Commit with:

```bash
git commit -m "feat: add directory transfers"
```
