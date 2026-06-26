# Transfer Completion Directory Refresh Spec

## Purpose

wetrans can enqueue uploads/downloads, execute SFTP transfers, and show task status in the global transfer queue. The current browser panels do not know when a task finishes, so a successful upload or download can leave the visible directory stale until the user manually refreshes.

This slice closes that MVP loop: when a transfer succeeds, the matching visible panel refreshes automatically.

## Product Boundary

This is a transfer completion refresh slice. It does not add drag-and-drop, conflict prompts, folder transfers, queue reordering, background notifications, or automatic refresh for directories that are not currently visible.

## In Scope

- Publish transfer task status changes from `TransferQueue`.
- Let browser code observe successful transfer completion events.
- Refresh the current remote panel after a successful upload when:
  - the completed task belongs to the currently selected host
  - the remote panel is currently showing the task's destination directory
- Refresh the current local panel after a successful download when:
  - the completed task belongs to the currently selected host
  - the local panel is currently showing the task's destination directory
- Refresh the transfer queue view model when events arrive so row status stays fresh.
- Ignore failed and cancelled tasks for directory refresh.
- Keep transfer execution independent from host switching.

## Out of Scope

- Refreshing hidden host session directories in the background.
- Directory refresh for failed or cancelled transfers.
- File conflict handling.
- Folder upload/download.
- Drag-and-drop transfer.
- Toasts or notifications.
- Debouncing/coalescing many completions into one refresh. This is deferred until burst refreshes prove noisy in testing.

## Event Model

Add a lightweight queue event model:

```swift
public struct TransferQueueEvent: Equatable, Sendable {
    public let task: TransferTask
}
```

For this slice the event only needs the finished task snapshot. A future version can add an explicit event kind if the queue starts publishing enqueue/progress/cancel/fail events.

`TransferQueue` exposes an `AsyncStream<TransferQueueEvent>`:

```swift
public func events() -> AsyncStream<TransferQueueEvent>
```

Rules:

- An event is emitted after a task reaches `succeeded`.
- The emitted task has final progress, byte counts, status, and completion time.
- Failed and cancelled tasks do not emit completion refresh events.
- Multiple listeners may subscribe.
- Event delivery must not block the queue actor or transfer engine.

## Browser Behavior

`MainBrowserViewModel` starts a queue observer when initialized.

When it receives a successful upload event:

```text
if selectedHost.id == task.hostId
and remotePanel.path == parent directory of task.remotePath
then refreshRemote()
```

When it receives a successful download event:

```text
if selectedHost.id == task.hostId
and localPanel.path == parent directory of task.localPath
then refreshLocal()
```

In all cases, the transfer queue view model refreshes so the footer/table reflects the latest task state.

## Host Switching Rules

If the user switches hosts while a transfer is running:

- the transfer continues
- completion events still fire
- the currently visible panels refresh only if they match the completed task's host and directory
- stale hidden directories are not loaded in the background

This keeps the behavior simple and avoids surprising network work for non-visible hosts.

## Error Handling

- If an automatic remote refresh fails, the remote panel shows the same readable error state as a manual refresh.
- If an automatic local refresh fails, the local panel shows the same readable error state as a manual refresh.
- Queue event delivery failure is not surfaced in the UI because `AsyncStream` completion is not expected during normal runtime.

## Testing

Add focused tests for:

- `TransferQueue` emits an event after success.
- `TransferQueue` does not emit events for failed/cancelled tasks.
- `MainBrowserViewModel` refreshes the visible remote directory after upload success.
- `MainBrowserViewModel` refreshes the visible local directory after download success.
- `MainBrowserViewModel` does not refresh when the completed task belongs to another host or another visible directory.

## Acceptance Criteria

- Successful upload refreshes the visible remote destination directory.
- Successful download refreshes the visible local destination directory.
- Failed and cancelled transfers do not trigger directory refresh.
- Transfers for non-selected hosts do not refresh the current panels.
- Transfers for non-visible directories do not refresh the current panels.
- Queue UI state refreshes after completion events.
- `swift test` and `swift build` pass.
