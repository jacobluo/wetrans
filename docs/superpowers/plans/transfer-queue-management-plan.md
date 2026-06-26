# Transfer Queue Management UI Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an expandable bottom transfer queue panel with task rows and queue management actions.

**Architecture:** Extend `TransferQueue` with single-task terminal removal. Expand `TransferQueueViewModel` from summary-only state into row view state and action methods. Replace the compact-only SwiftUI footer with a collapsed/expanded bottom panel that follows the ardot queue design.

**Tech Stack:** SwiftUI, Swift concurrency, XCTest, NSPasteboard for copying errors.

---

## File Structure

- Modify `wetrans/TransferQueue/TransferQueue.swift`: add `removeFinished(taskId:)`.
- Modify `wetrans/UI/TransferQueue/TransferQueueViewModel.swift`: add expanded state, row view state, formatting, and action methods.
- Modify `wetrans/UI/TransferQueue/TransferQueueSummaryView.swift`: render collapsed summary and expanded table-like queue panel.
- Test `wetransTests/TransferQueue/TransferQueueTests.swift`: single terminal task removal and active task protection.
- Test `wetransTests/UI/TransferQueueViewModelTests.swift`: rows, formatting, expansion, actions, copyable error.
- Test `wetransTests/UI/FilePanelViewTests.swift`: main browser still renders with expanded-capable queue.

## Task 1: Queue Removal Primitive

- [x] Write failing tests for `removeFinished(taskId:)`.
- [x] Run `swift test --filter TransferQueueTests`.
- [x] Implement `removeFinished(taskId:)` so it removes succeeded/failed/cancelled only.
- [x] Re-run `swift test --filter TransferQueueTests`.

## Task 2: Queue View Model Rows and Actions

- [x] Write failing tests for row formatting, expansion toggling, cancel, retry, remove, and clear actions.
- [x] Run `swift test --filter TransferQueueViewModelTests`.
- [x] Implement `TransferQueueRowViewState` and view model methods.
- [x] Re-run `swift test --filter TransferQueueViewModelTests`.

## Task 3: Expanded Queue SwiftUI Panel

- [x] Update render tests for the expanded-capable queue view.
- [x] Run `swift test --filter FilePanelViewTests`.
- [x] Implement collapsed and expanded queue UI in `TransferQueueSummaryView`.
- [x] Re-run `swift test --filter FilePanelViewTests`.

## Final Verification

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Commit, push, and open PR.
