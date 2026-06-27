# App State, Session Lifecycle, and Packaging Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Align docs with the current MVP behavior, tighten saved-host cleanup, add app-level coordination state, implement idle session disconnection, and provide a Developer ID packaging path.

**Architecture:** Keep cleanup orchestration in a small UI-facing maintenance service so `ConnectHostSheetView` does not manually coordinate every persistence/security/session module. Add `AppState` as a lightweight `ObservableObject` for shell state only. Extend `HostSessionManager` with an explicit idle-disconnect API and let the main browser schedule it.

**Tech Stack:** Swift, SwiftUI, Swift concurrency, XCTest, bash packaging scripts, macOS `codesign`/`notarytool`/`stapler`.

---

### Task 1: Align Product Docs With Current Implementation

**Files:**
- Modify: `docs/prd.md`
- Modify: `docs/architecture-design.md`
- Modify: `docs/data-model.md`
- Modify: `docs/technical-selection.md`
- Modify: `docs/implementation-plan.md`

- [x] **Step 1: Update file conflict wording**

Replace PRD text that says MVP blocks existing destination files with wording that the current MVP writes to the requested destination and does not yet offer conflict prompts.

- [x] **Step 2: Update file-panel architecture wording**

Clarify that the current MVP file panels are SwiftUI-rendered list surfaces with narrow AppKit integrations, while a future AppKit table replacement remains optional.

- [x] **Step 3: Remove favorite remote path product claims**

Remove user-facing P1/current claims for favorite remote paths while leaving data-model references that describe the existing field.

- [x] **Step 4: Update error and JSON persistence wording**

Document the current typed-enum/string-message error model and current temporary-file replacement persistence strategy without claiming stable error codes, recovery suggestions, debug-detail objects, fsync, backups, or bounded pruning.

### Task 2: Saved Host Cleanup and Auth-Type Credential Cleanup

**Files:**
- Create: `wetrans/UI/HostManagement/SavedHostMaintenance.swift`
- Modify: `wetrans/UI/HostManagement/HostOnboardingViews.swift`
- Modify: `wetransTests/UI/ConnectHostViewModelTests.swift`

- [x] **Step 1: Write failing cleanup tests**

Tests should assert that deleting a saved host removes catalog metadata, credentials, trusted host keys, and any runtime session. Tests should also assert that saving an edited host with a changed auth type deletes old credentials.

- [x] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter ConnectHostViewModelTests`

Expected: FAIL because `SavedHostMaintenance` and `HostSessionCleaning` do not exist yet.

- [x] **Step 3: Implement `SavedHostMaintenance`**

Create a small `@MainActor` service with:

```swift
public protocol HostSessionCleaning: Sendable {
    func disconnect(hostId: UUID) async
}

@MainActor
public final class SavedHostMaintenance {
    public func delete(_ host: SavedHost) async throws
    public func saveEdited(original: SavedHost, edited: SavedHost) async throws
}
```

- [x] **Step 4: Wire Connect Host sheet through the maintenance service**

`ConnectHostSheetView` should receive a `SavedHostMaintenance` dependency and call it from delete/edit flows.

- [x] **Step 5: Re-run focused tests**

Run: `swift test --filter ConnectHostViewModelTests`

Expected: PASS.

### Task 3: AppState

**Files:**
- Create: `wetrans/AppState.swift`
- Modify: `wetransTests/UI/ConnectHostViewModelTests.swift`
- Modify: `wetransApp/ContentView.swift`

- [x] **Step 1: Write failing AppState test**

Test sheet presentation, selected host ID, transfer queue expansion, and app error message mutation.

- [x] **Step 2: Run focused test and verify failure**

Run: `swift test --filter ConnectHostViewModelTests/testAppStateTracksConnectHostPresentationAndSelection`

Expected: FAIL because `AppState` does not exist yet.

- [x] **Step 3: Implement `AppState`**

`AppState` should be `@MainActor public final class AppState: ObservableObject` with published state and small methods for presentation, selected host, transfer queue expansion, and app error.

- [x] **Step 4: Wire `ContentView` to `AppState`**

Replace local `@State private var isShowingConnectHost` with `@StateObject private var appState = AppState()`.

- [x] **Step 5: Re-run focused test**

Run: `swift test --filter ConnectHostViewModelTests/testAppStateTracksConnectHostPresentationAndSelection`

Expected: PASS.

### Task 4: Idle Session Disconnect

**Files:**
- Modify: `wetrans/RemoteFileSystem/HostSessionManager.swift`
- Modify: `wetrans/UI/FileBrowsing/MainBrowserView.swift`
- Modify: `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`

- [x] **Step 1: Write failing idle disconnect tests**

Tests should connect two hosts, mark one old and one recent, call `disconnectIdleSessions(now:idleTimeout:)`, and assert only the old host disconnects while path state remains.

- [x] **Step 2: Run focused tests and verify failure**

Run: `swift test --filter HostSessionManagerTests`

Expected: FAIL because idle disconnect API does not exist.

- [x] **Step 3: Implement idle disconnect API**

Add:

```swift
public func disconnectIdleSessions(now: Date = Date(), idleTimeout: TimeInterval = 15 * 60) async
```

It should disconnect cached sessions whose `lastActiveAt` is older than `idleTimeout`.

- [x] **Step 4: Schedule idle cleanup from browser view**

Add a `.task` loop in `MainBrowserView` that sleeps on a conservative interval and calls `viewModel.disconnectIdleSessions()`.

- [x] **Step 5: Re-run focused tests**

Run: `swift test --filter HostSessionManagerTests`

Expected: PASS.

### Task 5: Developer ID Packaging Path

**Files:**
- Create: `scripts/package`
- Modify: `README.md`
- Modify: `docs/technical-selection.md`

- [x] **Step 1: Add packaging script**

Create `scripts/package` that builds `dist/wetrans.app`, optionally signs with `WETRANS_DEVELOPER_ID_APPLICATION`, zips the app, optionally submits with `WETRANS_NOTARYTOOL_PROFILE`, and staples on success.

- [x] **Step 2: Run packaging without credentials**

Run: `scripts/package`

Expected: builds `dist/wetrans.app`, creates `dist/wetrans.zip`, and reports signing/notarization skipped.

- [x] **Step 3: Document packaging environment variables**

Update README and technical-selection docs with the package command and optional signing/notarization variables.

### Task 6: Final Verification

**Files:**
- All changed files.

- [x] **Step 1: Run focused tests**

Run:

```bash
swift test --filter ConnectHostViewModelTests
swift test --filter HostSessionManagerTests
```

Expected: PASS.

- [x] **Step 2: Run full verification**

Run: `scripts/verify`

Expected: PASS.

- [x] **Step 3: Review docs for requested deferrals**

Confirm docs still leave these as not implemented/deferred: full UI E2E by default, drag-and-drop, expanded logs/debug detail/checklist.
