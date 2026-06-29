# File Copy Paste Delete Spec

## Purpose

Add desktop-native file operation actions to the three-pane browser so users can copy, paste, and delete files or folders from both local and remote panels.

## Product Boundary

This slice covers context-menu file operations in the current browser panels. It does not add drag-and-drop, global menu command routing, conflict prompts, undo, progress UI for remote-to-remote copies, or rename.

## In Scope

- Copy one row, or the current selected row group when the clicked row is selected.
- Paste copied items into the current directory of either panel.
- Delete one row, or the current selected row group when the clicked row is selected.
- Local-to-local paste uses the local filesystem.
- Remote-to-remote paste uses SFTP copy through the active session.
- Local-to-remote paste enqueues upload transfer tasks.
- Remote-to-local paste enqueues download transfer tasks.
- Local delete moves items to the macOS Trash.
- Remote delete permanently removes files or recursively removes folders over SFTP.
- After successful local file operations, refresh the local panel.
- After successful remote file operations, refresh the remote panel.
- Surface readable panel errors when operations fail.

## Out of Scope

- System-wide pasteboard file promises.
- Keyboard shortcuts and main menu command validation.
- Remote Trash semantics.
- Conflict resolution prompts.
- Same-folder automatic duplicate naming beyond the current directory listing.
- Cross-host remote copy.

## UI Behavior

Local row context menu:

```text
Upload
Copy
Paste
Delete
Show in Finder
Refresh
```

Remote row context menu:

```text
Download
Copy
Paste
Delete
Copy Remote Path
Refresh
```

Rules:

- `Copy` stores an in-app clipboard of file items and their source panel.
- `Paste` is enabled when there is an in-app clipboard and the target operation is valid.
- Pasting into the same directory uses a non-conflicting name such as `file copy.txt` or `folder copy`.
- `Delete` is destructive. Local delete moves to Trash; remote delete is permanent.
- `Delete` opens a confirmation dialog before any local or remote delete is executed.
- Remote clipboard entries are bound to the selected host at copy time. Pasting remote entries after switching hosts fails with a readable error.

## Architecture

Extend filesystem protocols at the operation boundary:

```swift
public protocol LocalFileSystem: Sendable {
    func listDirectory(_ path: String) throws -> [FileItem]
    func copyItem(at sourcePath: String, to destinationPath: String) throws
    func deleteItem(at path: String) throws
}

public protocol RemoteFileSystem: Sendable {
    func copyItem(from sourcePath: String, to destinationPath: String, in session: RemoteSession) async throws
    func deleteItem(_ item: FileItem, in session: RemoteSession) async throws
}
```

`HostSessionManager` owns session reuse and exposes remote copy/delete helpers. `MainBrowserViewModel` owns the in-app clipboard and delegates real operations to `LocalFileSystem`, `HostSessionManager`, and `TransferQueue`.

## Testing

Add focused tests for:

- Copying a selected local group and pasting to local calls local copy with non-conflicting destinations.
- Copying a selected remote group and pasting to remote calls remote copy with non-conflicting destinations.
- Pasting local copied folders into remote enqueues upload tasks.
- Pasting remote copied folders into local enqueues download tasks.
- Deleting local selected items calls local delete and refreshes local.
- Deleting remote selected items calls remote delete and refreshes remote.
- Delete context actions create a confirmation request, and delete only happens after the request is confirmed.
- Remote operation adapters delegate to connected libssh2 clients.
- FileManager local copy and Trash delete behavior is covered without touching user files.
- Real Docker-backed SFTP integration covers remote file copy, directory copy, file delete, directory delete, and cleanup.

## Acceptance Criteria

- Local and remote rows expose Copy, Paste, and Delete context actions.
- Files and folders can be copied and pasted within the same panel.
- Files and folders can be copied and pasted across local/remote panels through the transfer queue.
- Local files/folders can be deleted to Trash.
- Remote files/folders can be deleted recursively.
- Existing upload/download/reveal/copy path actions still work.
- Focused Swift tests and `scripts/verify` pass or any blocker is reported.
