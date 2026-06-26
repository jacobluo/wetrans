# Context Menu Actions Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add row-level local and remote file context menu actions for upload, download, Finder reveal, remote path copy, and refresh.

**Architecture:** Keep SwiftUI context menu rendering inside `FilePanelView`, and keep behavior in `MainBrowserViewModel`. AppKit integrations are isolated behind `FileRevealer` and `PasteboardWriting` protocols so tests can use fakes.

**Tech Stack:** SwiftUI, AppKit adapters, Swift concurrency, XCTest.

---

## File Structure

- Create `wetrans/Support/FileRevealer.swift`: protocol plus AppKit `NSWorkspaceFileRevealer`.
- Create `wetrans/Support/PasteboardWriting.swift`: protocol plus AppKit `SystemPasteboardWriter`.
- Modify `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`: inject support adapters and add row-scoped action methods.
- Modify `wetrans/UI/FileBrowsing/FilePanelView.swift`: add `FilePanelContextAction` and render row context menus.
- Modify `wetrans/UI/FileBrowsing/MainBrowserView.swift`: provide local and remote context action lists.
- Test `wetransTests/UI/MainBrowserViewModelTests.swift`: row-scoped upload/download, directory errors, reveal, copy path.
- Test `wetransTests/UI/FilePanelViewTests.swift`: context-action-capable panel renders.

## Task 1: Support Adapters

- [x] **Step 1: Write failing view model tests for reveal and copy**

Add to `wetransTests/UI/MainBrowserViewModelTests.swift`:

```swift
func testRevealLocalItemUsesInjectedFileRevealer() {
    let revealer = RecordingFileRevealer()
    let viewModel = makeViewModel(fileRevealer: revealer)
    let item = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false)

    viewModel.revealLocalItemInFinder(item)

    XCTAssertEqual(revealer.revealedPaths, ["/Users/me/Downloads/config.yaml"])
}

func testCopyRemotePathUsesInjectedPasteboardWriter() {
    let pasteboard = RecordingPasteboardWriter()
    let viewModel = makeViewModel(pasteboardWriter: pasteboard)
    let item = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false)

    viewModel.copyRemotePath(item)

    XCTAssertEqual(pasteboard.strings, ["/var/log/app.log"])
}
```

Add fake helpers near the other test fakes:

```swift
private final class RecordingFileRevealer: FileRevealer, @unchecked Sendable {
    private(set) var revealedPaths: [String] = []

    func reveal(path: String) {
        revealedPaths.append(path)
    }
}

private final class RecordingPasteboardWriter: PasteboardWriting, @unchecked Sendable {
    private(set) var strings: [String] = []

    func writeString(_ value: String) {
        strings.append(value)
    }
}
```

Extend both `makeViewModel` helpers with:

```swift
fileRevealer: FileRevealer = RecordingFileRevealer(),
pasteboardWriter: PasteboardWriting = RecordingPasteboardWriter()
```

and pass them to `MainBrowserViewModel`.

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: compile failure because `FileRevealer`, `PasteboardWriting`, `revealLocalItemInFinder`, and `copyRemotePath` do not exist.

- [x] **Step 3: Implement support adapter protocols**

Create `wetrans/Support/FileRevealer.swift`:

```swift
import AppKit
import Foundation

public protocol FileRevealer: Sendable {
    func reveal(path: String)
}

public struct NSWorkspaceFileRevealer: FileRevealer {
    public init() {}

    public func reveal(path: String) {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }
}
```

Create `wetrans/Support/PasteboardWriting.swift`:

```swift
import AppKit
import Foundation

public protocol PasteboardWriting: Sendable {
    func writeString(_ value: String)
}

public struct SystemPasteboardWriter: PasteboardWriting {
    public init() {}

    public func writeString(_ value: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(value, forType: .string)
    }
}
```

- [x] **Step 4: Inject adapters and add methods**

Modify `MainBrowserViewModel` to add properties:

```swift
private let fileRevealer: FileRevealer
private let pasteboardWriter: PasteboardWriting
```

Update the convenience initializer to pass:

```swift
fileRevealer: NSWorkspaceFileRevealer(),
pasteboardWriter: SystemPasteboardWriter()
```

Update the designated initializer parameters:

```swift
fileRevealer: FileRevealer = NSWorkspaceFileRevealer(),
pasteboardWriter: PasteboardWriting = SystemPasteboardWriter(),
```

Store them and add:

```swift
public func revealLocalItemInFinder(_ item: FileItem) {
    fileRevealer.reveal(path: item.path)
}

public func copyRemotePath(_ item: FileItem) {
    pasteboardWriter.writeString(item.path)
}
```

- [x] **Step 5: Re-run tests**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: PASS.

- [x] **Step 6: Commit support adapters**

Run:

```bash
git add wetrans/Support/FileRevealer.swift wetrans/Support/PasteboardWriting.swift wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetransTests/UI/MainBrowserViewModelTests.swift
git commit -m "feat: add file action support adapters"
```

## Task 2: Row-Scoped Upload and Download

- [x] **Step 1: Write failing row action tests**

Add to `wetransTests/UI/MainBrowserViewModelTests.swift`:

```swift
func testContextUploadEnqueuesOnlyClickedLocalFile() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let clicked = FileItem(name: "config.yaml", path: "/Users/me/Downloads/config.yaml", isDirectory: false, size: 12)
    let other = FileItem(name: "other.yaml", path: "/Users/me/Downloads/other.yaml", isDirectory: false, size: 20)
    let transferQueue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(
        hosts: [host],
        localFileSystem: FakeLocalFileSystem(listingsByPath: ["/Users/me/Downloads": [clicked, other]]),
        remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/project": []]),
        transferQueue: transferQueue
    )

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    viewModel.refreshLocal()
    await viewModel.refreshRemote()
    await viewModel.enqueueUpload(clicked)

    let tasks = await transferQueue.snapshot()
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/config.yaml")
    XCTAssertEqual(tasks[0].remotePath, "/project/config.yaml")
}

func testContextDownloadEnqueuesOnlyClickedRemoteFile() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
    let clicked = FileItem(name: "app.log", path: "/var/log/app.log", isDirectory: false, size: 42)
    let transferQueue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(
        hosts: [host],
        remoteFileSystem: MockRemoteFileSystem(listingsByPath: ["/var/log": [clicked]]),
        transferQueue: transferQueue
    )

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.refreshRemote()
    await viewModel.enqueueDownload(clicked)

    let tasks = await transferQueue.snapshot()
    XCTAssertEqual(tasks.count, 1)
    XCTAssertEqual(tasks[0].remotePath, "/var/log/app.log")
    XCTAssertEqual(tasks[0].localPath, "/Users/me/Downloads/app.log")
}

func testContextUploadRejectsDirectory() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let directory = FileItem(name: "folder", path: "/Users/me/Downloads/folder", isDirectory: true)
    let transferQueue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(hosts: [host], transferQueue: transferQueue)

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.enqueueUpload(directory)

    XCTAssertTrue(viewModel.localPanel.errorMessage.contains("Select a file to upload"))
    XCTAssertEqual(await transferQueue.snapshot(), [])
}

func testContextDownloadRejectsDirectory() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/var/log", lastLocalPath: "/Users/me/Downloads")
    let directory = FileItem(name: "logs", path: "/var/log/logs", isDirectory: true)
    let transferQueue = TransferQueue(engine: RecordingTransferEngine())
    let viewModel = makeViewModel(hosts: [host], transferQueue: transferQueue)

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.enqueueDownload(directory)

    XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Select a file to download"))
    XCTAssertEqual(await transferQueue.snapshot(), [])
}
```

- [x] **Step 2: Run tests to verify they fail**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: compile failure because `enqueueUpload(_:)` and `enqueueDownload(_:)` do not exist.

- [x] **Step 3: Implement row-scoped task methods**

Add to `MainBrowserViewModel`:

```swift
public func enqueueUpload(_ item: FileItem) async {
    guard let host = selectedHost else {
        localPanel.loadingState = .failed("Select a host before uploading files.")
        return
    }
    guard !item.isDirectory else {
        localPanel.loadingState = .failed("Select a file to upload.")
        return
    }

    await enqueueUploadTasks([
        TransferTask(
            hostId: host.id,
            hostDisplayName: host.displayName,
            direction: .upload,
            localPath: item.path,
            remotePath: BrowserPath.remoteJoin(directory: remotePanel.path, name: item.name),
            fileName: item.name,
            totalBytes: item.size
        )
    ])
}

public func enqueueDownload(_ item: FileItem) async {
    guard let host = selectedHost else {
        remotePanel.loadingState = .failed("Select a host before downloading files.")
        return
    }
    guard !item.isDirectory else {
        remotePanel.loadingState = .failed("Select a file to download.")
        return
    }

    await enqueueDownloadTasks([
        TransferTask(
            hostId: host.id,
            hostDisplayName: host.displayName,
            direction: .download,
            localPath: BrowserPath.localJoin(directory: localPanel.path, name: item.name),
            remotePath: item.path,
            fileName: item.name,
            totalBytes: item.size
        )
    ])
}
```

Extract helpers used by both row and selection actions:

```swift
private func enqueueUploadTasks(_ tasks: [TransferTask]) async {
    guard !tasks.isEmpty else {
        localPanel.loadingState = .failed("Select one or more files to upload.")
        return
    }
    await transferQueue.enqueue(tasks)
    await transferQueueViewModel.refresh()
}

private func enqueueDownloadTasks(_ tasks: [TransferTask]) async {
    guard !tasks.isEmpty else {
        remotePanel.loadingState = .failed("Select one or more files to download.")
        return
    }
    await transferQueue.enqueue(tasks)
    await transferQueueViewModel.refresh()
}
```

Update `enqueueUploadSelection()` and `enqueueDownloadSelection()` to build arrays and call the helpers.

- [x] **Step 4: Re-run tests**

Run:

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: PASS.

- [x] **Step 5: Commit row action behavior**

Run:

```bash
git add wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetransTests/UI/MainBrowserViewModelTests.swift
git commit -m "feat: add row scoped transfer actions"
```

## Task 3: SwiftUI Context Menus

- [x] **Step 1: Write failing render test**

Add to `wetransTests/UI/FilePanelViewTests.swift`:

```swift
func testFilePanelViewCanRenderContextActions() {
    let state = FilePanelState(
        title: "Local",
        path: "/tmp",
        loadingState: .loaded([
            FileItem(name: "config.yaml", path: "/tmp/config.yaml", isDirectory: false)
        ])
    )

    let view = FilePanelView(
        state: state,
        contextActions: { item in
            [
                FilePanelContextAction(
                    id: "upload-\(item.id)",
                    title: "Upload",
                    systemImage: "arrow.up.circle",
                    isEnabled: true,
                    perform: {}
                )
            ]
        },
        onRefresh: {},
        onGoUp: {},
        onSelect: { _ in },
        onOpen: { _ in }
    )

    XCTAssertNotNil(String(describing: type(of: view.body)))
}
```

- [x] **Step 2: Run render tests to verify failure**

Run:

```bash
swift test --filter FilePanelViewTests
```

Expected: compile failure because `FilePanelContextAction` and `contextActions` do not exist.

- [x] **Step 3: Implement `FilePanelContextAction` and row menus**

Modify `wetrans/UI/FileBrowsing/FilePanelView.swift`:

```swift
public struct FilePanelContextAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isEnabled: Bool
    public let perform: () -> Void
}
```

Add a stored property:

```swift
private let contextActions: (FileItem) -> [FilePanelContextAction]
```

Update initializer with default:

```swift
contextActions: @escaping (FileItem) -> [FilePanelContextAction] = { _ in [] },
```

In `fileList`, attach:

```swift
.contextMenu {
    ForEach(contextActions(item)) { action in
        Button {
            action.perform()
        } label: {
            Label(action.title, systemImage: action.systemImage)
        }
        .disabled(!action.isEnabled)
    }
}
```

- [x] **Step 4: Wire actions in `MainBrowserView`**

For the local panel, pass:

```swift
contextActions: { item in
    [
        FilePanelContextAction(
            id: "upload-\(item.id)",
            title: "Upload",
            systemImage: "arrow.up.circle",
            isEnabled: viewModel.selectedHost != nil && !item.isDirectory,
            perform: {
                Task { await viewModel.enqueueUpload(item) }
            }
        ),
        FilePanelContextAction(
            id: "reveal-\(item.id)",
            title: "Show in Finder",
            systemImage: "magnifyingglass",
            isEnabled: true,
            perform: {
                viewModel.revealLocalItemInFinder(item)
            }
        ),
        FilePanelContextAction(
            id: "refresh-local-\(item.id)",
            title: "Refresh",
            systemImage: "arrow.clockwise",
            isEnabled: true,
            perform: viewModel.refreshLocal
        )
    ]
}
```

For the remote panel, pass:

```swift
contextActions: { item in
    [
        FilePanelContextAction(
            id: "download-\(item.id)",
            title: "Download",
            systemImage: "arrow.down.circle",
            isEnabled: viewModel.selectedHost != nil && !item.isDirectory,
            perform: {
                Task { await viewModel.enqueueDownload(item) }
            }
        ),
        FilePanelContextAction(
            id: "copy-path-\(item.id)",
            title: "Copy Remote Path",
            systemImage: "doc.on.doc",
            isEnabled: true,
            perform: {
                viewModel.copyRemotePath(item)
            }
        ),
        FilePanelContextAction(
            id: "refresh-remote-\(item.id)",
            title: "Refresh",
            systemImage: "arrow.clockwise",
            isEnabled: true,
            perform: {
                Task { await viewModel.refreshRemote() }
            }
        )
    ]
}
```

- [x] **Step 5: Re-run render tests**

Run:

```bash
swift test --filter FilePanelViewTests
```

Expected: PASS.

- [x] **Step 6: Commit context menu UI**

Run:

```bash
git add wetrans/UI/FileBrowsing/FilePanelView.swift wetrans/UI/FileBrowsing/MainBrowserView.swift wetransTests/UI/FilePanelViewTests.swift
git commit -m "feat: add file panel context menus"
```

## Final Verification

- [x] Run `swift test`.
- [x] Run `swift build`.
- [x] Commit, push, and open PR.
