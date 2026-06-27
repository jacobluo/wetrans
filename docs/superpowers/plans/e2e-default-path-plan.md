# E2E Default Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make `scripts/e2e` prove the default real-host transfer path and packaged app smoke path.

**Architecture:** Extend the existing `RemoteFileSystemRealHostIntegrationTests` instead of creating a separate network harness. Keep direct SFTP E2E and native app smoke as separate layers under `scripts/e2e`, with full UI automation still gated by environment variables.

**Tech Stack:** Swift, XCTest, SwiftPM, libssh2 SFTP, Bash scripts, macOS Accessibility runner.

---

## Task 1: Real Host Transfer E2E

**Files:**
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`

- [x] **Step 1: Write failing real-host transfer test**

Add `testConfiguredRealHostsUploadAndDownloadFilesAndDirectories` to `RemoteFileSystemRealHostIntegrationTests`. The test should load the same integration config as connect/list, iterate each host, and call a helper that verifies upload/download of single file, multiple files, and a directory with a nested child directory.

Expected fixture shape:

```text
source/
  single.txt
  multi-a.txt
  multi-b.txt
  folder/
    root-a.txt
    nested/
      nested-a.txt
      nested-b.txt
```

The helper should use a unique remote root like `/tmp/wetrans-e2e-\(UUID().uuidString)` and download into a separate local temporary directory.

- [x] **Step 2: Verify red**

Run:

```bash
swift test --filter RemoteFileSystemRealHostIntegrationTests/testConfiguredRealHostsUploadAndDownloadFilesAndDirectories
```

Expected: FAIL because the test method and helper do not exist yet.

- [x] **Step 3: Implement local fixture helpers**

Add helpers in the test file:

```swift
private struct E2EFixture {
    let sourceRoot: URL
    let single: URL
    let multiple: [URL]
    let directory: URL
    let expectedDirectoryRelativePaths: [String: Data]
}
```

Create deterministic files using `Data("...\n".utf8)` so downloads can be compared byte-for-byte.

- [x] **Step 4: Implement upload/download assertions**

Use the existing `LibSSH2RemoteFileSystem` adapter to:

- connect and list the host path
- upload `single.txt` to `remoteRoot/uploads/single/single.txt`
- upload `multi-a.txt` and `multi-b.txt` to `remoteRoot/uploads/multiple/`
- upload all files under `folder/` to `remoteRoot/uploads/directory/folder/...`
- download the uploaded single file into a local `downloads/single/`
- download the uploaded multiple files into `downloads/multiple/`
- download the uploaded directory files into `downloads/directory/folder/...`
- compare downloaded file contents with the original source data
- list remote directories to assert expected uploaded file names are visible

- [x] **Step 5: Verify green**

Run:

```bash
swift test --filter RemoteFileSystemRealHostIntegrationTests/testConfiguredRealHostsUploadAndDownloadFilesAndDirectories
```

Expected: PASS against the configured OpenCloud VM.

- [x] **Step 6: Commit**

Commit with:

```bash
git add wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift
git commit -m "test: add real host transfer e2e"
```

## Task 2: E2E Script Default Path

**Files:**
- Modify: `scripts/e2e`

- [x] **Step 1: Write failing script expectation**

Update `scripts/e2e` so the default path runs:

```bash
swift test --filter RemoteFileSystemRealHostIntegrationTests
"$ROOT/script/build_and_run.sh" --verify
swift run wetrans-e2e smoke
```

Keep the existing `WETRANS_E2E_RUN_FULL=1` block after smoke.

- [x] **Step 2: Run script**

Run:

```bash
scripts/e2e
```

Expected before implementation: FAIL or omit the new transfer test because the script has not yet been updated.

- [x] **Step 3: Implement script order**

Put real-host SFTP E2E first, then app build/run smoke. This keeps network/credential failures separate from packaged app launch failures.

- [x] **Step 4: Verify script**

Run:

```bash
scripts/e2e
```

Expected: PASS with real-host tests and app smoke.

- [x] **Step 5: Commit**

Commit with:

```bash
git add scripts/e2e
git commit -m "test: run real host e2e by default"
```

## Task 3: Documentation Updates

**Files:**
- Modify: `docs/prd.md`
- Modify: `docs/architecture-design.md`
- Modify: `docs/implementation-plan.md`
- Modify: `docs/real-host-sftp-smoke.md`
- Modify: `.codebuddy/rules/testing.mdc`

- [x] **Step 1: Update project documentation**

Document that the default E2E path has two layers:

- direct real-host SFTP transfer E2E for connect/list/upload/download
- packaged app build/run smoke through the native Accessibility runner

Keep full UI transfer automation described as opt-in with `WETRANS_E2E_RUN_FULL=1`.

- [x] **Step 2: Verify docs diff**

Run:

```bash
git diff --check
```

Expected: PASS.

- [x] **Step 3: Commit**

Commit with:

```bash
git add docs/prd.md docs/architecture-design.md docs/implementation-plan.md docs/real-host-sftp-smoke.md .codebuddy/rules/testing.mdc
git commit -m "docs: update e2e testing strategy"
```

## Task 4: Final Verification

- [ ] **Step 1: Run focused real-host E2E**

Run:

```bash
swift test --filter RemoteFileSystemRealHostIntegrationTests
```

Expected: PASS.

- [ ] **Step 2: Run E2E script**

Run:

```bash
scripts/e2e
```

Expected: PASS.

- [ ] **Step 3: Run full verification**

Run:

```bash
scripts/verify
```

Expected: PASS.

- [ ] **Step 4: Close spec and plan**

Update `docs/superpowers/specs/e2e-default-path-spec.md` to `Status: Closed` and mark this plan complete.

- [ ] **Step 5: Commit and push**

Commit with:

```bash
git add docs/superpowers/specs/e2e-default-path-spec.md docs/superpowers/plans/e2e-default-path-plan.md
git commit -m "docs: close e2e default path spec"
git push
```
