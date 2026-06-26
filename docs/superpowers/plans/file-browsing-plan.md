# File Browsing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace placeholder file panes with a usable three-pane local/remote browsing experience.

**Architecture:** Keep libssh2, Keychain, JSON, and filesystem details behind existing services. Add a `MainBrowserViewModel` that coordinates `HostCatalog`, `HostSidebarViewModel`, `HostSessionManager`, and `LocalFileSystem`, then render it through small SwiftUI views.

**Tech Stack:** Swift, SwiftUI, Combine, SwiftPM, XCTest.

---

## Source Spec

- `docs/superpowers/specs/file-browsing-spec.md`
- `docs/implementation-plan.md`
- `docs/architecture-design.md`

## File Map

Create or modify:

```text
wetrans/Support/ApplicationSupport.swift
wetrans/UI/FileBrowsing/BrowserPath.swift
wetrans/UI/FileBrowsing/FilePanelState.swift
wetrans/UI/FileBrowsing/MainBrowserViewModel.swift
wetrans/UI/FileBrowsing/FilePanelView.swift
wetrans/UI/FileBrowsing/MainBrowserView.swift
wetransApp/ContentView.swift
wetransTests/UI/BrowserPathTests.swift
wetransTests/UI/MainBrowserViewModelTests.swift
wetransTests/UI/FilePanelViewTests.swift
docs/superpowers/plans/file-browsing-plan.md
```

## Task 1: Browsing State and Path Helpers

**Files:**

- Create: `wetrans/UI/FileBrowsing/BrowserPath.swift`
- Create: `wetrans/UI/FileBrowsing/FilePanelState.swift`
- Test: `wetransTests/UI/BrowserPathTests.swift`

- [x] **Step 1: Write failing path/state tests**

Tests must cover:

```swift
XCTAssertEqual(BrowserPath.remoteParent(of: "/var/log"), "/var")
XCTAssertEqual(BrowserPath.remoteParent(of: "/"), "/")
XCTAssertEqual(BrowserPath.remoteJoin(directory: "/", name: "etc"), "/etc")
XCTAssertEqual(BrowserPath.remoteJoin(directory: "/var", name: "log"), "/var/log")
XCTAssertEqual(BrowserPath.localParent(of: "/Users/me/Downloads"), "/Users/me")
XCTAssertEqual(FilePanelState(title: "Local", path: "/tmp").loadingState, .idle)
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter BrowserPathTests
```

Expected: FAIL because types are missing.

- [x] **Step 3: Implement helpers and state**

Implement:

- `BrowserPath.remoteParent(of:)`
- `BrowserPath.remoteJoin(directory:name:)`
- `BrowserPath.localParent(of:)`
- `BrowserPath.localJoin(directory:name:)`
- `FilePanelLoadingState`
- `FilePanelState`

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter BrowserPathTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/UI/FileBrowsing/BrowserPath.swift wetrans/UI/FileBrowsing/FilePanelState.swift wetransTests/UI/BrowserPathTests.swift docs/superpowers/plans/file-browsing-plan.md
git commit -m "feat: add file browsing state helpers"
```

## Task 2: Main Browser View Model

**Files:**

- Create: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Create: `wetrans/Support/ApplicationSupport.swift`
- Test: `wetransTests/UI/MainBrowserViewModelTests.swift`

- [x] **Step 1: Write failing view model tests**

Tests must cover:

```swift
try viewModel.loadHosts()
viewModel.select(hostId: host.id)
XCTAssertEqual(viewModel.selectedHost?.id, host.id)
XCTAssertEqual(viewModel.localPanel.path, "/Users/me/Downloads")
XCTAssertEqual(viewModel.remotePanel.path, "/project")

viewModel.refreshLocal()
XCTAssertEqual(viewModel.localPanel.loadingState, .loaded(localItems))

viewModel.openLocalItem(localFolder)
XCTAssertEqual(viewModel.localPanel.path, "/Users/me/Downloads/folder")

await viewModel.refreshRemote()
XCTAssertEqual(viewModel.remotePanel.loadingState, .loaded(remoteItems))

await viewModel.openRemoteItem(remoteFolder)
XCTAssertEqual(viewModel.remotePanel.path, "/project/logs")
```

Also test:

```swift
remoteFileSystem.listErrorsByPath["/project"] = RemoteFileSystemError.hostKeyRequiresTrust(candidate)
await viewModel.refreshRemote()
XCTAssertEqual(viewModel.remotePanel.path, "/project")
XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Host key requires confirmation"))
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: FAIL because `MainBrowserViewModel` is missing.

- [x] **Step 3: Implement view model**

Implement a `@MainActor final class MainBrowserViewModel: ObservableObject` that:

- Loads hosts from `HostCatalog`.
- Updates `HostSidebarViewModel`.
- Selects a host by id.
- Restores per-host local and remote path from `HostSessionManager.state(for:)`.
- Refreshes local panel through `LocalFileSystem`.
- Refreshes remote panel through `HostSessionManager`.
- Opens directories by updating local/remote path and refreshing.
- Selects file items without transfer behavior.
- Maps errors to readable `failed` state strings.

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter MainBrowserViewModelTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/Support/ApplicationSupport.swift wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetransTests/UI/MainBrowserViewModelTests.swift docs/superpowers/plans/file-browsing-plan.md
git commit -m "feat: add main browser view model"
```

## Task 3: File Panel SwiftUI Views

**Files:**

- Create: `wetrans/UI/FileBrowsing/FilePanelView.swift`
- Test: `wetransTests/UI/FilePanelViewTests.swift`

- [x] **Step 1: Write failing view compile tests**

Tests must instantiate the local and remote panel surfaces:

```swift
let state = FilePanelState(title: "Local", path: "/tmp", loadingState: .loaded([FileItem(name: "folder", path: "/tmp/folder", isDirectory: true)]))
let view = FilePanelView(state: state, onRefresh: {}, onGoUp: {}, onOpen: { _ in })
XCTAssertNotNil(view)
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter FilePanelViewTests
```

Expected: FAIL because `FilePanelView` is missing.

- [x] **Step 3: Implement `FilePanelView`**

Build a compact macOS SwiftUI panel:

- title/path header
- icon-only go-up and refresh buttons with help text
- list rows with folder/file icon, name, size, modified date, and permissions
- loading/empty/failed states
- double-click item open through `.onTapGesture(count: 2)`

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter FilePanelViewTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/UI/FileBrowsing/FilePanelView.swift wetransTests/UI/FilePanelViewTests.swift docs/superpowers/plans/file-browsing-plan.md
git commit -m "feat: add file panel views"
```

## Task 4: Main Browser Composition

**Files:**

- Create: `wetrans/UI/FileBrowsing/MainBrowserView.swift`
- Modify: `wetransApp/ContentView.swift`
- Test: `wetransTests/UI/FilePanelViewTests.swift`

- [x] **Step 1: Write failing composition compile test**

Add:

```swift
let viewModel = MainBrowserViewModel(...)
let view = MainBrowserView(viewModel: viewModel, onConnectHost: {})
XCTAssertNotNil(view)
```

- [x] **Step 2: Run test to verify it fails**

```bash
swift test --filter FilePanelViewTests
```

Expected: FAIL because `MainBrowserView` is missing.

- [x] **Step 3: Implement main composition**

Implement:

- `MainBrowserView` with `NavigationSplitView`, existing `HostSidebarView`, two `FilePanelView` panes in `HSplitView`, and bottom `TransferQueuePlaceholder`.
- `ContentView` as a thin wrapper that owns `MainBrowserViewModel` and shows `ConnectHostDialogView`.
- `.task` load hosts on launch.
- `.onChange` bridge sidebar selection to `viewModel.select(hostId:)`.

- [x] **Step 4: Run test to verify it passes**

```bash
swift test --filter FilePanelViewTests
```

Expected: PASS.

- [x] **Step 5: Commit**

```bash
git add wetrans/UI/FileBrowsing/MainBrowserView.swift wetransApp/ContentView.swift wetransTests/UI/FilePanelViewTests.swift docs/superpowers/plans/file-browsing-plan.md
git commit -m "feat: wire three pane file browser"
```

## Task 5: Final Verification

- [ ] **Step 1: Run all tests**

```bash
swift test
```

Expected: PASS.

- [ ] **Step 2: Run build**

```bash
swift build
```

Expected: PASS.

- [ ] **Step 3: Review changed files**

```bash
git diff --stat main..HEAD
git status --short
```

Expected: changed files match this plan and working tree is clean.

- [ ] **Step 4: Mark plan complete and commit if needed**

```bash
git add docs/superpowers/plans/file-browsing-plan.md
git commit -m "docs: mark file browsing plan complete"
```

## Self-Review Notes

Out-of-scope items intentionally untouched:

- Upload and download.
- Drag and drop.
- Transfer queue behavior.
- Remote mutation commands.
- AppKit table replacement.
