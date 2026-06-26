# Transfer Completion Directory Refresh Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Refresh the visible local or remote browser panel when a transfer succeeds into the directory currently being viewed.

**Architecture:** `TransferQueue` publishes lightweight success events through an `AsyncStream`. `MainBrowserViewModel` observes those events, refreshes queue state, and refreshes only the matching visible browser panel. Transfer execution remains global and independent from host switching.

**Tech Stack:** Swift concurrency, `AsyncStream`, SwiftUI view models, XCTest.

---

## File Structure

- Modify `wetrans/TransferQueue/TransferQueue.swift`: add transfer success event publication and listener management.
- Create or modify `wetrans/TransferQueue/TransferQueueEvent.swift`: define the queue event value.
- Modify `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`: observe queue events and refresh matching panels.
- Test `wetransTests/TransferQueue/TransferQueueTests.swift`: queue emits success events and does not emit failure/cancel refresh events.
- Test `wetransTests/UI/MainBrowserViewModelTests.swift`: browser refreshes visible matching panels only.

## Task 1: Transfer Queue Success Events

- [ ] **Step 1: Write failing queue event tests**

Add tests to `wetransTests/TransferQueue/TransferQueueTests.swift`:

```swift
func testEmitsEventWhenTaskSucceeds() async throws {
    let engine = RecordingTransferEngine()
    let queue = TransferQueue(engine: engine)
    let events = await queue.events()
    let eventTask = Task<TransferTask?, Never> {
        for await event in events {
            return event.task
        }
        return nil
    }
    let task = makeTask(status: .pending, totalBytes: 10)

    await queue.enqueue([task])
    try await Task.sleep(nanoseconds: 20_000_000)

    let emitted = await eventTask.value
    XCTAssertEqual(emitted?.id, task.id)
    XCTAssertEqual(emitted?.status, .succeeded)
    XCTAssertEqual(emitted?.progress, 1)
}

func testDoesNotEmitEventWhenTaskFails() async throws {
    let queue = TransferQueue(engine: FailingTransferEngine(error: TransferQueueError.engineUnavailable))
    let events = await queue.events()
    let eventTask = Task<TransferTask?, Never> {
        for await event in events {
            return event.task
        }
        return nil
    }

    await queue.enqueue([makeTask(status: .pending)])
    try await Task.sleep(nanoseconds: 20_000_000)
    eventTask.cancel()

    let emitted = await eventTask.value
    XCTAssertNil(emitted)
}
```

- [ ] **Step 2: Run queue tests to verify they fail**

Run:

```bash
swift test --filter TransferQueueTests
```

Expected: compile failure or test failure because `TransferQueueEvent` / `events()` does not exist.

- [ ] **Step 3: Implement queue event stream**

Add `wetrans/TransferQueue/TransferQueueEvent.swift`:

```swift
import Foundation

public struct TransferQueueEvent: Equatable, Sendable {
    public let task: TransferTask

    public init(task: TransferTask) {
        self.task = task
    }
}
```

Modify `TransferQueue`:

```swift
private var eventContinuations: [UUID: AsyncStream<TransferQueueEvent>.Continuation] = [:]

public func events() -> AsyncStream<TransferQueueEvent> {
    let id = UUID()
    return AsyncStream { continuation in
        eventContinuations[id] = continuation
        continuation.onTermination = { [weak self] _ in
            Task { await self?.removeEventContinuation(id: id) }
        }
    }
}

private func removeEventContinuation(id: UUID) {
    eventContinuations.removeValue(forKey: id)
}

private func emit(_ event: TransferQueueEvent) {
    for continuation in eventContinuations.values {
        continuation.yield(event)
    }
}
```

In `finish(taskId:)`, after `persist()` and before `schedule()`, call:

```swift
emit(TransferQueueEvent(task: tasks[index]))
```

Do not emit from `fail(taskId:)` or cancellation paths.

- [ ] **Step 4: Re-run queue tests**

Run:

```bash
swift test --filter TransferQueueTests
```

Expected: PASS.

- [ ] **Step 5: Commit queue event changes**

Run:

```bash
git add wetrans/TransferQueue/TransferQueue.swift wetrans/TransferQueue/TransferQueueEvent.swift wetransTests/TransferQueue/TransferQueueTests.swift
git commit -m "feat: publish transfer completion events"
```

## Task 2: Browser Refresh on Completion

- [ ] **Step 1: Write failing browser refresh tests**

Add tests to `wetransTests/UI/MainBrowserViewModelTests.swift`:

```swift
func testSuccessfulUploadRefreshesVisibleRemoteDirectory() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let localFile = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
    let remoteFileSystem = MockRemoteFileSystem(listingsByPath: [
        "/project": [],
    ])
    let queue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(
        hosts: [host],
        localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [localFile]]),
        remoteFileSystem: remoteFileSystem,
        transferQueue: queue
    )

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    viewModel.refreshLocal()
    await viewModel.refreshRemote()
    viewModel.selectLocalItem(localFile)
    await viewModel.enqueueUploadSelection()
    try await waitUntil {
        remoteFileSystem.listCalls.map(\.path).filter { $0 == "/project" }.count >= 2
    }
}

func testSuccessfulDownloadRefreshesVisibleLocalDirectory() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
    let remoteFile = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
    let localFileSystem = FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": []])
    let queue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(
        hosts: [host],
        localFileSystem: localFileSystem,
        remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [remoteFile]]),
        transferQueue: queue
    )

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    viewModel.refreshLocal()
    await viewModel.refreshRemote()
    viewModel.selectRemoteItem(remoteFile)
    await viewModel.enqueueDownloadSelection()
    try await waitUntil {
        localFileSystem.listCalls.filter { $0 == "/Users/me/Downloads" }.count >= 2
    }
}

func testTransferForDifferentVisibleDirectoryDoesNotRefreshPanels() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let queue = TransferQueue(engine: RecordingTransferEngine())
    let remoteFileSystem = MockRemoteFileSystem(listingsByPath: ["/project": []])
    let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem, transferQueue: queue)

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.refreshRemote()
    await queue.enqueue([
        TransferTask(
            hostId: host.id,
            hostDisplayName: host.displayName,
            direction: .upload,
            localPath: "/Users/me/config.yaml",
            remotePath: "/other/config.yaml",
            fileName: "config.yaml",
            totalBytes: 12
        )
    ])
    try await Task.sleep(nanoseconds: 40_000_000)

    XCTAssertEqual(remoteFileSystem.listCalls.map(\.path), ["/project"])
}
```

Add a helper if it does not already exist in the file:

```swift
@MainActor
private func waitUntil(
    timeout: TimeInterval = 2,
    condition: @escaping @MainActor () async -> Bool
) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
        if await condition() {
            return
        }
        try await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for condition")
}
```

- [ ] **Step 2: Run browser tests to verify they fail**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: upload/download refresh tests fail because `MainBrowserViewModel` does not observe queue completion events.

- [ ] **Step 3: Observe queue events in `MainBrowserViewModel`**

Add a property:

```swift
private var transferQueueEventsTask: Task<Void, Never>?
```

In `init(...)`, after `transferQueueViewModel` is created:

```swift
startTransferQueueEventObservation()
```

Add:

```swift
deinit {
    transferQueueEventsTask?.cancel()
}

private func startTransferQueueEventObservation() {
    transferQueueEventsTask?.cancel()
    transferQueueEventsTask = Task { [weak self, transferQueue] in
        let events = await transferQueue.events()
        for await event in events {
            await self?.handleTransferQueueEvent(event)
        }
    }
}

private func handleTransferQueueEvent(_ event: TransferQueueEvent) async {
    await transferQueueViewModel.refresh()
    guard event.task.status == .succeeded else {
        return
    }
    guard selectedHost?.id == event.task.hostId else {
        return
    }

    switch event.task.direction {
    case .upload:
        let destinationDirectory = BrowserPath.remoteParent(of: event.task.remotePath)
        guard remotePanel.path == destinationDirectory else {
            return
        }
        await refreshRemote()
    case .download:
        let destinationDirectory = BrowserPath.localParent(of: event.task.localPath)
        guard localPanel.path == destinationDirectory else {
            return
        }
        refreshLocal()
    }
}
```

- [ ] **Step 4: Re-run browser tests**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: PASS.

- [ ] **Step 5: Commit browser refresh changes**

Run:

```bash
git add wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetransTests/UI/MainBrowserViewModelTests.swift
git commit -m "feat: refresh browser after transfer completion"
```

## Final Verification

- [ ] Run `swift test`.
- [ ] Run `swift build`.
- [ ] Commit, push, and open PR.
