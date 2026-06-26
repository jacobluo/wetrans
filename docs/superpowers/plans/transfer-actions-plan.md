# Transfer Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add upload/download buttons in the file browser that enqueue selected files into the global transfer queue.

**Architecture:** Keep transfer task creation in `MainBrowserViewModel`, because it owns selected host, local path, remote path, and panel selection state. Expose selection and toolbar actions through `FilePanelView` without introducing drag/drop yet.

**Tech Stack:** SwiftUI, Swift concurrency, XCTest.

---

## File Structure

- Modify `wetrans/UI/FileBrowsing/FilePanelView.swift`: single selection and optional toolbar action button.
- Modify `wetrans/UI/FileBrowsing/FilePanelState.swift`: helper for loaded/selected items.
- Modify `wetrans/UI/FileBrowsing/MainBrowserView.swift`: pass selection and transfer action closures.
- Modify `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`: enqueue upload/download tasks.
- Test `wetransTests/UI/MainBrowserViewModelTests.swift`: task mapping and error behavior.
- Test `wetransTests/UI/FilePanelViewTests.swift`: rendering with transfer action.

## Task 1: Selection Helpers and Queue Injection

- [x] Write failing tests for selecting local/remote files and enqueuing upload/download tasks.
- [x] Run `swift test --filter MainBrowserViewModelTests`.
- [x] Add `TransferQueue` injection and panel selection methods.
- [x] Re-run `swift test --filter MainBrowserViewModelTests`.

## Task 2: Upload/Download Actions

- [x] Write failing tests for upload/download task path mapping, directory filtering, no-host errors, and summary refresh.
- [x] Run `swift test --filter MainBrowserViewModelTests`.
- [x] Implement `enqueueUploadSelection()` and `enqueueDownloadSelection()`.
- [x] Re-run `swift test --filter MainBrowserViewModelTests`.

## Task 3: Browser UI Buttons

- [x] Write/update render tests for file panel action button.
- [x] Run `swift test --filter FilePanelViewTests`.
- [x] Add optional file panel action button and wire main browser actions.
- [x] Re-run `swift test --filter FilePanelViewTests`.

## Final Verification

- [x] Run `swift test`
- [x] Run `swift build`
- [x] Commit, push, and open PR.
