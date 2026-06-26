# Transfer Queue Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the global transfer queue control plane for wetrans with bounded concurrency, progress, cancellation, retry, history persistence, and a compact browser footer.

**Architecture:** Add a `TransferQueue` module around a `TransferEngine` protocol. The queue is an actor that owns mutable task state and scheduling; UI reads snapshots through a `TransferQueueViewModel`. Persistence uses the existing `TransferHistoryDocument` and `JSONDocumentStore`.

**Tech Stack:** Swift 6, Swift concurrency, SwiftUI, XCTest, JSON persistence.

---

## File Structure

- Create `wetrans/TransferQueue/TransferEngine.swift`: engine and progress contracts.
- Create `wetrans/TransferQueue/TransferQueue.swift`: actor that schedules, mutates, cancels, retries, clears, and persists tasks.
- Create `wetrans/TransferQueue/TransferHistoryStore.swift`: small persistence protocol and JSON-backed implementation.
- Create `wetrans/UI/TransferQueue/TransferQueueViewModel.swift`: main-actor summary state for SwiftUI.
- Create `wetrans/UI/TransferQueue/TransferQueueSummaryView.swift`: compact bottom queue view.
- Modify `wetrans/UI/FileBrowsing/MainBrowserView.swift`: replace placeholder with queue summary view.
- Modify `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`: create and expose queue view model.
- Test `wetransTests/TransferQueue/TransferQueueTests.swift`: queue scheduling, progress, cancel, retry, history.
- Test `wetransTests/UI/TransferQueueViewModelTests.swift`: summary counts and refresh.

## Task 1: Queue Engine Contract

**Files:**
- Create: `wetrans/TransferQueue/TransferEngine.swift`
- Test: `wetransTests/TransferQueue/TransferQueueTests.swift`

- [ ] **Step 1: Write failing tests for enqueue and progress**

Add tests that create a controllable engine, enqueue upload/download tasks, verify tasks start, and verify progress updates one task.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransferQueueTests`

Expected: compile failure because `TransferQueue`, `TransferEngine`, and `TransferProgress` do not exist.

- [ ] **Step 3: Add minimal engine and queue types**

Create `TransferProgress`, `TransferEngine`, and a `TransferQueue` actor with `enqueue`, `snapshot`, and basic run-to-success behavior.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TransferQueueTests`

Expected: queue tests pass.

## Task 2: Concurrency, Cancellation, and Retry

**Files:**
- Modify: `wetrans/TransferQueue/TransferQueue.swift`
- Test: `wetransTests/TransferQueue/TransferQueueTests.swift`

- [ ] **Step 1: Write failing tests**

Add tests for global limit, per-host limit, pending cancellation, running cancellation, failed task retry, and clearing terminal tasks.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransferQueueTests`

Expected: assertions fail because queue scheduling is not complete.

- [ ] **Step 3: Implement scheduling behavior**

Track running Swift tasks by task id, enforce both concurrency limits, implement `cancel`, `retry`, and `clearFinished`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TransferQueueTests`

Expected: all transfer queue tests pass.

## Task 3: Transfer History Persistence

**Files:**
- Create: `wetrans/TransferQueue/TransferHistoryStore.swift`
- Modify: `wetrans/TransferQueue/TransferQueue.swift`
- Test: `wetransTests/TransferQueue/TransferQueueTests.swift`

- [ ] **Step 1: Write failing persistence tests**

Add tests for startup normalization of previous `running` tasks and save-after-state-transition.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransferQueueTests`

Expected: compile or assertion failure because history store integration is absent.

- [ ] **Step 3: Implement persistence**

Add `TransferHistoryStore`, `FileTransferHistoryStore`, queue initialization from stored tasks, and best-effort save calls after mutations.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TransferQueueTests`

Expected: all transfer queue tests pass.

## Task 4: Queue Summary UI

**Files:**
- Create: `wetrans/UI/TransferQueue/TransferQueueViewModel.swift`
- Create: `wetrans/UI/TransferQueue/TransferQueueSummaryView.swift`
- Modify: `wetrans/UI/FileBrowsing/MainBrowserView.swift`
- Modify: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Test: `wetransTests/UI/TransferQueueViewModelTests.swift`

- [ ] **Step 1: Write failing UI model tests**

Add tests for empty summary, upload/download/running/failed counts, and refresh from queue snapshot.

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter TransferQueueViewModelTests`

Expected: compile failure because the UI model does not exist.

- [ ] **Step 3: Implement view model and summary view**

Create `TransferQueueViewModel`, create the compact summary view, expose it from `MainBrowserViewModel`, and replace `TransferQueuePlaceholder`.

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter TransferQueueViewModelTests`

Expected: UI model tests pass.

## Final Verification

- [ ] Run `swift test`
- [ ] Run `swift build`
- [ ] Commit implementation
- [ ] Push branch
- [ ] Open PR
