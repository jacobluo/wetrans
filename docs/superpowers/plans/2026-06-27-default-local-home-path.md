# Default Local Home Path Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Change the startup default local file panel path from Downloads to the current user's home directory while preserving saved per-host local paths.

**Architecture:** The default local path is injected into `MainBrowserViewModel` and `HostSessionManager`. Update both default closures to return `FileManager.default.homeDirectoryForCurrentUser.path`; keep existing `host.lastLocalPath` precedence unchanged.

**Tech Stack:** Swift, SwiftPM, XCTest, macOS `FileManager`.

---

### Task 1: Document and Test Home Default

**Files:**
- Modify: `docs/superpowers/specs/file-browsing-spec.md`
- Modify: `wetransTests/UI/MainBrowserViewModelTests.swift`
- Modify: `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`

- [x] **Step 1: Update file browsing spec**

Change default local path priority to: current host state, host `lastLocalPath`, home directory.

- [x] **Step 2: Write failing view-model test**

Add a test asserting `MainBrowserViewModel` initializes `localPanel.path` to `FileManager.default.homeDirectoryForCurrentUser.path` when no explicit `defaultLocalPath` is injected.

- [x] **Step 3: Write failing session-manager test**

Add a test asserting `HostSessionManager.state(for:)` uses `FileManager.default.homeDirectoryForCurrentUser.path` when the host has no saved local path and no explicit `defaultLocalPath` is injected.

- [x] **Step 4: Run focused tests and verify red**

Run: `swift test --filter MainBrowserViewModelTests/testDefaultInitializerUsesHomeDirectoryForInitialLocalPath --filter HostSessionManagerTests/testInitialStateUsesHomeDirectoryWhenHostHasNoSavedLocalPath`

Expected: FAIL because production defaults still use Downloads.

### Task 2: Implement Home Default

**Files:**
- Modify: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Modify: `wetrans/RemoteFileSystem/HostSessionManager.swift`
- Modify: `docs/superpowers/plans/2026-06-27-default-local-home-path.md`

- [x] **Step 1: Update `MainBrowserViewModel` default closure**

Replace the Downloads-first default with `FileManager.default.homeDirectoryForCurrentUser.path`.

- [x] **Step 2: Update `HostSessionManager` default closure**

Replace the Downloads-first default with `FileManager.default.homeDirectoryForCurrentUser.path`.

- [x] **Step 3: Run focused tests and verify green**

Run: `swift test --filter MainBrowserViewModelTests --filter HostSessionManagerTests`

Expected: PASS.

- [x] **Step 4: Run build verification**

Run: `scripts/typecheck`

Expected: PASS.

- [x] **Step 5: Mark plan checkboxes complete**

Update this plan so completed steps are checked.
