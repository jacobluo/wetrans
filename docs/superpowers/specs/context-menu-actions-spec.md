# Context Menu Actions Spec

## Purpose

wetrans now has a functional three-pane browser, toolbar upload/download actions, a global transfer queue, and automatic refresh after successful transfers. The next internal-testing usability gap is desktop-native context menus: users expect right-click actions in file lists, especially on macOS.

This slice added row-level context menu actions for common MVP workflows. Directory upload/download semantics were later extended by `directory-transfers-spec.md`.

## Product Boundary

This is a context-menu usability slice. It does not add drag-and-drop, file conflict prompts, multi-select context menus, or remote file editing. Folder transfer behavior is now covered by `directory-transfers-spec.md`.

## In Scope

Local file panel row context menu:

- Upload selected row to the current remote directory.
- Show selected row in Finder.
- Refresh local directory.

Remote file panel row context menu:

- Download selected row to the current local directory.
- Copy remote path.
- Refresh remote directory.

Shared behavior:

- Context menu actions are row-scoped for this slice.
- Upload/download context actions use the same file-or-directory transfer planning rules as toolbar actions.
- Context upload/download enqueue one or more file-level `TransferTask` values.
- Context upload/download refresh the transfer queue view model after enqueue.
- Finder reveal and pasteboard writes are isolated behind small protocols so view model behavior is testable without AppKit.

## Out of Scope

- Context actions for multiple selected rows.
- Drag-and-drop transfer.
- Directory transfer planning, which is covered by `directory-transfers-spec.md`.
- Conflict prompts.
- Remote "Reveal in Finder", which does not apply.
- Opening local or remote files in external editors.

## UI Behavior

### Local Row

Right-clicking a local file or directory shows:

```text
Upload
Show in Finder
Refresh
```

Rules:

- `Upload` is enabled for files and directories when a host is selected.
- `Show in Finder` is available for files and directories.
- `Refresh` refreshes the local panel's current directory.

### Remote Row

Right-clicking a remote file or directory shows:

```text
Download
Copy Remote Path
Refresh
```

Rules:

- `Download` is enabled for files and directories when a host is selected.
- `Copy Remote Path` copies the row path as plain text.
- `Refresh` refreshes the current remote panel directory.

## Architecture

Add a generic context action value next to `FilePanelAction`:

```swift
public struct FilePanelContextAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isEnabled: Bool
    public let perform: () -> Void
}
```

`FilePanelView` receives:

```swift
contextActions: (FileItem) -> [FilePanelContextAction]
```

The view renders those actions inside SwiftUI `.contextMenu`.

`MainBrowserView` maps local and remote rows to context action lists and delegates behavior to `MainBrowserViewModel`.

Add support adapters:

```swift
public protocol FileRevealer: Sendable {
    func reveal(path: String)
}

public protocol PasteboardWriting: Sendable {
    func writeString(_ value: String)
}
```

Production implementations use AppKit:

- `NSWorkspace.shared.activateFileViewerSelecting`
- `NSPasteboard.general`

Tests use fakes.

## View Model Behavior

Add row-scoped methods:

```swift
public func enqueueUpload(_ item: FileItem) async
public func enqueueDownload(_ item: FileItem) async
public func revealLocalItemInFinder(_ item: FileItem)
public func copyRemotePath(_ item: FileItem)
```

Upload/download logic should reuse the same task-building rules as existing selection-based actions:

- file upload destination is `remotePanel.path + item.name`
- file download destination is `localPanel.path + item.name`
- directories are recursively expanded by `DirectoryTransferPlanner`
- missing selected host is rejected with readable errors

## Error Handling

- Uploading an empty directory from the context menu surfaces the same empty-task message as toolbar upload.
- Downloading an empty directory from the context menu surfaces the same empty-task message as toolbar download.
- Uploading without a selected host sets a local panel error.
- Downloading without a selected host sets a remote panel error.
- Copying a remote path has no user-visible success message in this slice.
- Finder reveal has no user-visible success message in this slice.

## Testing

Add focused tests for:

- Local row upload enqueues exactly one upload task for that row.
- Remote row download enqueues exactly one download task for that row.
- Directory upload/download from context menu expands contained files into transfer tasks.
- Local reveal calls the injected file revealer with the item path.
- Remote copy path writes the item path to the injected pasteboard writer.
- `FilePanelView` can render context-action-capable rows.

## Acceptance Criteria

- Local rows expose Upload, Show in Finder, and Refresh context menu actions.
- Remote rows expose Download, Copy Remote Path, and Refresh context menu actions.
- Row-scoped file upload/download create one transfer task with correct paths.
- Row-scoped directory upload/download create one task per contained file while preserving the top-level directory name.
- Show in Finder is delegated to the file revealer adapter.
- Copy Remote Path is delegated to the pasteboard adapter.
- Existing toolbar upload/download behavior still works.
- `swift test` and `swift build` pass.
