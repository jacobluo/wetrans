# Stale SFTP Session Reconnect Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically recover once when a cached SFTP session fails during remote directory listing after idle time or network loss.

**Architecture:** Keep `HostSessionManager` as the session ownership boundary. On `RemoteFileSystemError.connectionFailed` from `listDirectory` against an existing cached session, disconnect that session, clear it from the cache, reconnect through the existing `session(for:)` path, and retry the same list once.

**Tech Stack:** Swift 6, SwiftPM, XCTest, existing `RemoteFileSystem` protocol and `HostSessionManager`.

---

### Task 1: Reconnect Stale Listing Session

**Files:**
- Modify: `wetrans/RemoteFileSystem/HostSessionManager.swift`
- Modify: `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`
- Create: `docs/superpowers/specs/stale-sftp-session-reconnect-spec.md`
- Create: `docs/superpowers/plans/stale-sftp-session-reconnect-plan.md`

- [x] **Step 1: Write failing stale-session reconnect test**

Add a test to `HostSessionManagerTests` that creates a fake remote filesystem whose first list call fails with `RemoteFileSystemError.connectionFailed("Unable to send FXP_OPEN*")` and whose second list call succeeds. Assert that the manager connects twice, disconnects the stale session, lists the same path twice, and returns the second listing.

- [x] **Step 2: Verify red**

Run: `swift test --filter HostSessionManagerTests/testRemoteListingReconnectsOnceWhenCachedSessionFails`

Expected: FAIL because `HostSessionManager` currently returns the first listing error.

- [x] **Step 3: Implement single retry in HostSessionManager**

Add stale-session cleanup and one retry for `RemoteFileSystemError.connectionFailed` thrown by `listDirectory`.

- [x] **Step 4: Verify green**

Run: `swift test --filter HostSessionManagerTests/testRemoteListingReconnectsOnceWhenCachedSessionFails`

Expected: PASS.

- [x] **Step 5: Add non-retryable error guard test**

Add a test that `permissionDenied` from an existing session does not reconnect.

- [x] **Step 6: Verify focused tests**

Run:

```bash
swift test --filter HostSessionManagerTests/testRemoteListingReconnectsOnceWhenCachedSessionFails
swift test --filter HostSessionManagerTests/testRemoteListingDoesNotReconnectForPermissionDenied
```

Expected: PASS.

- [x] **Step 7: Run full verification**

Run: `scripts/verify`

Expected: PASS.

- [x] **Step 8: Commit**

Run:

```bash
git add docs/superpowers/specs/stale-sftp-session-reconnect-spec.md docs/superpowers/plans/stale-sftp-session-reconnect-plan.md wetrans/RemoteFileSystem/HostSessionManager.swift wetransTests/RemoteFileSystem/HostSessionManagerTests.swift
git commit -m "fix: reconnect stale SFTP sessions"
```
