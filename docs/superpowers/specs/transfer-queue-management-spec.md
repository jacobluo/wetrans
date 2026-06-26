# Transfer Queue Management UI Spec

## Purpose

wetrans already has a global transfer queue, real SFTP upload/download execution, and browser upload/download buttons. The current UI only shows a compact queue summary, so users cannot inspect individual tasks or act on failed/running transfers.

This slice adds the first queue management UI: expand/collapse the bottom queue, inspect task rows, cancel pending/running transfers, retry failed/cancelled transfers, clear terminal tasks, and view/copy readable errors.

## Design Source

Ardot MVP prototype: `cocraft://localhost/file/697398357828482?node_id=0%3A1`

Relevant ardot queue nodes:

- `2:95`: queue header with `Transfer Queue`, `Running 3`, `Failed 1`
- `2:102`: table header `File / Host / Direction / Progress / Speed / Status`
- `2:104`, `2:106`: running upload/download rows
- `2:108`: failed row with `Failed · Retry`
- `2:110`: concurrency hint `Global 3 running • per-host 2 • survives host switching`

Implementation should match the ardot direction: a dense macOS-native bottom panel, not a modal, drawer, or separate window.

## Product Boundary

This is a queue-management UI slice. It does not change transfer execution semantics and does not add drag-and-drop, conflict handling, folder transfers, or automatic directory refresh after completion.

## In Scope

- Expand/collapse the bottom transfer queue.
- Show compact summary when collapsed.
- Show a dense table-like list when expanded.
- Display each task's:
  - file name
  - host display name
  - direction
  - progress percentage
  - transferred/total bytes when available
  - speed
  - status
  - action
- Actions:
  - cancel pending or running task
  - retry failed or cancelled task
  - remove terminal task from view
  - clear succeeded tasks
  - clear failed/cancelled tasks
  - clear all terminal tasks
- Show failed task error message inline or through a lightweight popover/sheet.
- Copy failed task error text.
- Keep queue independent of current selected host.
- Refresh queue snapshot after actions.

## Out of Scope

- Pause/resume.
- Drag-and-drop upload/download.
- File conflict prompts.
- Folder transfers.
- Reordering queue tasks.
- Per-task priority.
- Directory refresh callbacks after transfer success.
- AppKit `NSTableView` replacement. SwiftUI table-like rows are acceptable for this slice.

## UI Behavior

### Collapsed

Collapsed footer remains one row:

```text
Transfer Queue   3 transfers · Upload 1 · Download 2 · Running 2 · Failed 1      [chevron]
```

It should show failed count in a red warning treatment when any failed task exists.

### Expanded

Expanded footer becomes a bottom panel with a header and rows:

```text
Transfer Queue        Running 3    Failed 1                         [Clear] [chevron]
File                  Host         Direction     Progress    Speed       Status      Action
config.yaml           dev          Upload        72%         1.2 MB/s    Running     Cancel
access.log            prod         Download      54%         860 KB/s    Running     Cancel
model.bin             gpu-a100     Download      0%          -           Failed      Retry
Global 3 running • per-host 2 • survives host switching
```

Rows should stay compact enough to fit the bottom area without feeling like a separate page.

### Empty State

When expanded and empty:

```text
No transfers yet
```

The compact collapsed text remains `No transfers`.

## Interaction Rules

- `Cancel` is visible for `pending` and `running`.
- `Retry` is visible for `failed` and `cancelled`.
- `Remove` is visible for terminal statuses: `succeeded`, `failed`, `cancelled`.
- `Clear Succeeded` removes succeeded tasks only.
- `Clear Failed` removes failed and cancelled tasks.
- `Clear Finished` removes succeeded, failed, and cancelled tasks.
- Running tasks cannot be removed directly; users must cancel first.
- Errors should use the queue's stored `errorMessage`, not raw stack traces.

## View Model Changes

Extend `TransferQueueViewModel` beyond summary-only state:

- track `isExpanded`
- expose `tasks: [TransferTask]`
- expose `rows: [TransferQueueRowViewState]`
- expose row action availability
- call queue methods:
  - `cancel(taskId:)`
  - `retry(taskId:)`
  - `remove(taskId:)`
  - `clearFinished(statuses:)`
- refresh snapshot after each action

If `TransferQueue` does not yet support removing one terminal task, add a focused method for it:

```swift
func removeFinished(taskId: UUID)
```

The method must ignore pending/running tasks.

## Formatting Rules

- Progress:
  - show integer percent from `progress`
  - clamp to `0...100`
- Speed:
  - use `ByteCountFormatter`
  - show `-` when unknown
- Bytes:
  - if total exists, show `transferred / total`
  - otherwise show transferred only
- Direction:
  - `Upload`
  - `Download`
- Status:
  - `Pending`
  - `Running`
  - `Succeeded`
  - `Failed`
  - `Cancelled`
  - `Paused`

## Error Handling

- Failed rows should visually stand out using subtle warning treatment, consistent with ardot's pale warning row.
- Error detail should be user-readable.
- Copying an empty error should be disabled.
- Queue persistence errors are still out of scope for UI display unless already exposed by the view model.

## Acceptance Criteria

- User can expand and collapse the transfer queue.
- Expanded queue lists all current tasks.
- Rows show file, host, direction, progress, speed, status, and action.
- Pending/running tasks can be cancelled from the UI.
- Failed/cancelled tasks can be retried from the UI.
- Terminal tasks can be removed from the UI.
- Clear controls remove the intended terminal task groups.
- Failed task errors can be viewed and copied.
- Running tasks cannot be removed without cancelling first.
- Queue summary updates after every action.
- `swift test` and `swift build` pass.
