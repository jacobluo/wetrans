# Transfer Queue Spec

## Purpose

wetrans needs a global transfer queue that survives host switching and can run multiple file transfers without binding task state to the currently selected host. This spec covers the first transfer-queue slice: queue core, progress/status state, bounded concurrency, retry/cancel behavior, transfer-history persistence, and a compact bottom queue UI.

## Product Boundary

This slice implements the queue as the control plane for uploads and downloads. Each selected file becomes one `TransferTask`; a multi-file upload or download is represented by multiple tasks in the same global queue.

The queue is global:

- switching hosts does not cancel running tasks
- tasks show their owning host
- completed, failed, and cancelled tasks remain visible until cleared
- finished task summaries are written to `transfer_history.json`

## In Scope

- A `TransferEngine` protocol that runs one `TransferTask` and reports progress.
- A `TransferQueue` actor that owns task state and scheduling.
- Global concurrency limit, default `3`.
- Per-host concurrency limit, default `2`.
- Enqueue one or many upload/download tasks.
- Progress updates for transferred bytes, progress ratio, and speed.
- Cancel pending and running tasks.
- Retry failed or cancelled tasks.
- Clear succeeded, failed, cancelled, or all finished tasks.
- Persist queue history through `TransferHistoryDocument`.
- A SwiftUI bottom queue summary view for the main browser.

## Out of Scope

- Actual libssh2 upload/download byte loops.
- Drag and drop upload/download gestures.
- Folder transfers.
- Pause/resume.
- Conflict prompts for overwrite/skip/rename.
- Resumable transfers.
- Rich expanded queue table.

Those items are follow-up specs after the queue engine boundary is stable.

## Model

Use existing domain models:

- `TransferTask`
- `TransferDirection`
- `TransferStatus`
- `TransferHistoryDocument`

Add:

```swift
public struct TransferProgress: Equatable, Sendable {
    public let transferredBytes: UInt64
    public let totalBytes: UInt64?
    public let speedBytesPerSecond: UInt64?
}

public protocol TransferEngine: Sendable {
    func run(
        task: TransferTask,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws
}
```

`TransferQueue` is the only owner of mutable task state. Engines receive a task snapshot and report progress back to the queue.

## Scheduling Behavior

When tasks are enqueued:

1. Tasks start as `pending`.
2. The queue starts as many tasks as allowed by global and per-host limits.
3. Running tasks update progress asynchronously.
4. A successful engine run marks the task `succeeded`.
5. A thrown error marks the task `failed` with a user-readable error.
6. Task cancellation marks the task `cancelled`.
7. Any terminal transition triggers another scheduling pass.

The queue must never start more than:

- `globalConcurrencyLimit` tasks total
- `perHostConcurrencyLimit` tasks for the same `hostId`

## Cancellation

Pending cancellation:

- status becomes `cancelled`
- `completedAt` is set
- the engine is never called

Running cancellation:

- the queue cancels the Swift task that is running the engine
- status becomes `cancelled`
- `completedAt` is set
- no retry happens automatically

## Retry

Retry is allowed for `failed` and `cancelled` tasks.

Retry resets:

- `status` to `pending`
- `transferredBytes` to `0`
- `progress` to `0`
- `speedBytesPerSecond` to `nil`
- `errorMessage` to `nil`
- `startedAt` to `nil`
- `completedAt` to `nil`

The task keeps its `id`, host, direction, and paths.

## Persistence

The queue loads from and saves to `TransferHistoryDocument`.

Startup normalization:

- `running` tasks from the previous launch become `failed`
- their `errorMessage` becomes `Transfer interrupted because wetrans was closed.`
- `startedAt` stays intact
- `completedAt` is set to startup time

Save after each state transition:

- enqueue
- start
- progress update
- succeeded
- failed
- cancelled
- retry
- clear

If saving fails, the queue should keep functioning in memory and expose the save error for UI diagnostics later. The MVP queue UI does not need to render this error yet.

## UI Behavior

The bottom queue view starts compact:

```text
Transfer Queue  Upload 1  Download 2  Failed 1  Running 3
```

It should:

- show total task count
- show running count
- show failed count
- show upload/download counts
- show an idle state when empty

Expanded task table is out of scope for this slice.

## Acceptance Criteria

- Upload and download tasks can be enqueued into one global queue.
- Queue state is independent of current host selection.
- Multiple tasks run concurrently up to configured limits.
- Per-host concurrency is enforced.
- Progress updates mutate only the owning task.
- Pending tasks can be cancelled before the engine runs.
- Running tasks can be cancelled.
- Failed and cancelled tasks can be retried.
- Finished tasks can be cleared.
- `transfer_history.json` persists terminal task summaries.
- Previous-launch running tasks are marked failed on startup.
- The main browser shows a bottom queue summary instead of a placeholder.
