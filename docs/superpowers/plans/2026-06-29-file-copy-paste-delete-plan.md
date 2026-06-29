# File Copy Paste Delete Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add local and remote copy, paste, and delete actions for files and folders in the three-pane browser.

**Architecture:** Keep UI as context-menu actions in `MainBrowserView`, with behavior owned by `MainBrowserViewModel`. Extend `LocalFileSystem`, `RemoteFileSystem`, `HostSessionManager`, and libssh2 client adapters so tests can verify filesystem operations without invoking AppKit or a real host.

**Tech Stack:** SwiftUI, Swift concurrency, SwiftPM, XCTest, FileManager, libssh2 SFTP.

---

## File Structure

- Modify `wetrans/FileSystem/LocalFileSystem.swift`: add copy/delete protocol requirements and local error cases.
- Modify `wetrans/FileSystem/FileManagerLocalFileSystem.swift`: implement recursive copy via `FileManager.copyItem` and local delete via `FileManager.trashItem`.
- Modify `wetrans/RemoteFileSystem/RemoteFileSystem.swift`: add copy/delete protocol requirements.
- Modify `wetrans/RemoteFileSystem/MockRemoteFileSystem.swift`: record copy/delete calls for tests.
- Modify `wetrans/RemoteFileSystem/HostSessionManager.swift`: expose active-session copy/delete helpers.
- Modify `wetrans/RemoteFileSystem/LibSSH2Client.swift`: add remote copy/delete methods.
- Modify `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`: delegate copy/delete to connected clients.
- Modify `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`: implement remote recursive copy/delete with SFTP read/write, mkdir, unlink, and rmdir.
- Modify `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`: add in-app clipboard, paste routing, delete routing, and duplicate destination naming.
- Modify `wetrans/UI/FileBrowsing/MainBrowserView.swift`: add Copy/Paste/Delete context menu actions.
- Test `wetransTests/UI/MainBrowserViewModelTests.swift`: view model copy/paste/delete behavior.
- Test `wetransTests/FileSystem/FileManagerLocalFileSystemTests.swift`: local copy and trash delete.
- Test `wetransTests/RemoteFileSystem/HostSessionManagerTests.swift`: session-manager copy/delete delegation.
- Test `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`: adapter copy/delete delegation.
- Test `wetransTests/UI/FilePanelViewTests.swift`: render context actions with new file operation entries.

## Task 1: View Model Operation Contract

- [x] **Step 1: Write failing `MainBrowserViewModelTests` for local copy/paste/delete.**

Add tests that copy a selected local group, paste into the local panel, and delete selected local items. Expected failure: `copyLocalItems`, `pasteIntoLocal`, `deleteLocalItems`, and `LocalFileSystem.copyItem/deleteItem` do not exist.

- [x] **Step 2: Run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: compile failure for the missing operation APIs.

- [x] **Step 3: Implement minimal local operation plumbing.**

Extend `LocalFileSystem`, `FileManagerLocalFileSystem`, test fakes, and `MainBrowserViewModel` enough for local copy/paste/delete tests to pass. Use non-conflicting destination names derived from the visible target listing.

- [x] **Step 4: Re-run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: local operation tests pass.

## Task 2: Remote Operation Contract

- [x] **Step 1: Write failing tests for remote copy/paste/delete.**

Add view model and host session tests that verify remote copy/delete delegation and remote-to-local/local-to-remote paste queue routing. Expected failure: remote protocol and session-manager helpers do not exist.

- [x] **Step 2: Run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests && swift test --filter HostSessionManagerTests`

Expected: compile failure for missing remote operation APIs.

- [x] **Step 3: Implement remote protocol, mock, session manager, and view model routing.**

Add `copyItem` and `deleteItem` to `RemoteFileSystem`, `MockRemoteFileSystem`, and `HostSessionManager`. Route same-side remote paste to remote copy and remote delete to session-manager delete.

- [x] **Step 4: Re-run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests && swift test --filter HostSessionManagerTests`

Expected: tests pass.

## Task 3: Production Adapters and UI Wiring

- [x] **Step 1: Write failing adapter tests.**

Add `LibSSH2RemoteFileSystemTests` for copy/delete delegation and `FileManagerLocalFileSystemTests` for local copy/delete.

- [x] **Step 2: Run focused tests.**

Run: `swift test --filter LibSSH2RemoteFileSystemTests && swift test --filter FileManagerLocalFileSystemTests`

Expected: compile failure for missing adapter methods.

- [x] **Step 3: Implement production adapters.**

Add libssh2 client copy/delete methods and dynamic SFTP implementation. Add `libssh2_sftp_unlink_ex` and `libssh2_sftp_rmdir_ex` symbols.

- [x] **Step 4: Wire context menus.**

Add Copy, Paste, and Delete actions to local and remote row context menus. Mark Delete with a trash icon and destructive role where the existing context action abstraction supports it.

- [x] **Step 5: Re-run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests && swift test --filter HostSessionManagerTests && swift test --filter LibSSH2RemoteFileSystemTests && swift test --filter FileManagerLocalFileSystemTests && swift test --filter FilePanelViewTests`

Expected: all focused tests pass.

## Task 4: Verification and Review

- [x] **Step 1: Run repository verification.**

Run: `scripts/verify`

Expected: lint, typecheck, unit tests, and default e2e path pass.

- [x] **Step 2: Review diff against spec.**

Check operation coverage, test realism, no secrets, and no unrelated file churn.

- [x] **Step 3: Update plan checkboxes.**

Mark completed steps in this plan before final handoff.

## Task 5: Real SFTP Copy/Delete Integration Coverage

- [x] **Step 1: Add real host integration test for remote copy and delete.**

Add `testConfiguredRealHostsCopyAndDeleteFilesAndDirectories` to `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`.

- [x] **Step 2: Run Docker-backed SFTP integration test.**

Run: `scripts/local-sftp-fixture -- swift test --filter wetransTests.RemoteFileSystemRealHostIntegrationTests`

Expected: PASS, including copy/delete for both configured local fixture hosts.

- [x] **Step 3: Re-run repository verification.**

Run: `scripts/verify`

Expected: lint, typecheck, unit tests, real SFTP integration, packaged app smoke, and UI smoke pass.

## Task 6: Delete Confirmation Dialog

- [x] **Step 1: Write failing view model confirmation tests.**

Add tests that verify local and remote delete context actions create a pending confirmation and do not delete until `confirmPendingDelete()` is called.

- [x] **Step 2: Run focused tests to verify RED.**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: compile failure for missing pending delete confirmation APIs.

- [x] **Step 3: Implement pending delete confirmation state.**

Add `FileDeleteConfirmation`, request/cancel/confirm methods, and route confirmed deletes through the existing local/remote delete paths.

- [x] **Step 4: Wire SwiftUI confirmation dialog.**

Change context menu Delete actions to request confirmation, and add a destructive `confirmationDialog` in `MainBrowserView`.

- [x] **Step 5: Run focused tests.**

Run: `swift test --filter MainBrowserViewModelTests && swift test --filter FilePanelViewTests`

Expected: PASS.
