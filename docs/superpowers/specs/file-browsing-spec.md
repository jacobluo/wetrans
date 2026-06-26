# File Browsing Spec

## 1. Purpose

This spec delivers the first usable three-pane browsing experience for wetrans.

Users should be able to:

- See saved hosts in the left sidebar.
- Select a host.
- Browse a local directory in the middle panel.
- Connect to the selected host and browse one remote directory in the right panel.
- Enter folders, go up, refresh, and preserve local/remote paths per host.

This slice is about browsing only. It does not implement upload, download, drag and drop, transfer queue behavior, remote mutation, or context menus.

## 2. Product Shape

The main window keeps the established structure:

```text
Left: Host Sidebar
Middle: Local File Panel
Right: Remote File Panel
Bottom: Transfer Queue Placeholder
```

The current ardot prototype removes the app-level top horizontal bar from the main browser. The sidebar is the persistent global navigation surface, while refresh, go up, upload, and download actions remain scoped to the relevant file panel.

The first browsing implementation should feel like an operational tool, not a landing page:

- Dense lists.
- Clear paths.
- Predictable toolbar actions.
- Visible loading and error states.
- No decorative hero content.
- No explanatory onboarding text inside the normal browsing surface.

## 3. Scope

### 3.1 In Scope

- Replace local and remote placeholders with real panels.
- List local directory contents through `LocalFileSystem`.
- List remote directory contents through `HostSessionManager`.
- Maintain selected host state through `HostSidebarViewModel`.
- Maintain per-host local and remote paths through `HostSessionManager`.
- Support:
  - refresh
  - go up
  - double-click / primary action to enter directories
  - empty directory state
  - loading state
  - readable error state
- Keep transfer queue as the existing placeholder.

### 3.2 Out of Scope

- Upload.
- Download.
- Drag and drop.
- File conflict handling.
- Multi-select transfer actions.
- Remote delete/rename/new folder.
- Local Finder reveal.
- Full AppKit table replacement.
- Host-key trust prompt UI beyond surfacing a structured error.
- Transfer queue implementation.

## 4. Design Direction

Use SwiftUI panels first, backed by focused view models.

This gives the product an end-to-end browsing loop quickly while keeping the file-panel logic isolated enough to replace the list body with AppKit later.

```text
ContentView
  -> HostSidebarView
  -> MainBrowserViewModel
      -> HostSidebarViewModel
      -> HostSessionManager
      -> LocalFileSystem
  -> LocalFilePanelView
  -> RemoteFilePanelView
```

The panel views should not know about libssh2, Keychain, JSON storage, or `ssh -G`.

## 5. View Model Boundaries

### 5.1 MainBrowserViewModel

Responsibilities:

- Own the currently selected host.
- Expose current local and remote panel states.
- Bridge host selection changes into per-host path restoration.
- Call local and remote loaders.
- Keep local and remote path updates in `HostSessionManager`.
- Convert low-level errors into displayable messages.

Suggested published state:

```swift
@Published var selectedHost: SavedHost?
@Published var localPanel: FilePanelState
@Published var remotePanel: FilePanelState
@Published var isRemoteAvailable: Bool
```

### 5.2 FilePanelState

One shared state model can back both panels:

```swift
enum FilePanelLoadingState: Equatable {
    case idle
    case loading
    case loaded([FileItem])
    case empty
    case failed(String)
}

struct FilePanelState: Equatable {
    var title: String
    var path: String
    var loadingState: FilePanelLoadingState
    var selectedItemIds: Set<String>
}
```

### 5.3 FilePanelView

Responsibilities:

- Render a compact title/path toolbar.
- Render refresh and go-up buttons using icons.
- Render a list of files with:
  - name
  - size
  - modified time
  - permissions when available
- Call closures for refresh, go up, and item open.

The panel should be generic enough to use for local and remote browsing.

## 6. Local Browsing Behavior

Default local path priority:

1. Current host state `currentLocalPath`.
2. Host `lastLocalPath`.
3. Downloads directory.
4. Home directory.

Actions:

- Refresh lists current local path.
- Go up moves to parent directory if one exists.
- Opening a directory updates the local path and refreshes.
- Opening a file selects it but does not preview or transfer it in this slice.

Errors:

- Local not-directory and cannot-read errors become readable `failed` states.
- Path state should not be cleared on error.

## 7. Remote Browsing Behavior

Default remote path priority is already owned by `HostSessionManager`:

1. Host `lastRemotePath`.
2. Host `defaultRemotePath`.
3. `~`.

Actions:

- Selecting a host restores that host's local and remote paths.
- Refresh calls `HostSessionManager.listRemoteDirectory(for:)`.
- Go up updates remote path to parent and refreshes.
- Opening a remote directory updates remote path and refreshes.
- Opening a remote file selects it but does not download it.

Errors:

- `.hostKeyRequiresTrust` shows a failed state that tells the user the host key needs confirmation.
- `.hostKeyChanged` shows a failed state that warns the host key changed.
- `.disconnected` shows a retryable failed state.
- Other connection/listing errors show readable text.

The app must not clear the stored remote path when remote loading fails.

## 8. Path Handling

Add small path helpers rather than scattering string logic through views.

Local path operations should use `URL(fileURLWithPath:)`.

Remote path operations should use a lightweight POSIX-style helper:

- parent of `/var/log` is `/var`
- parent of `/` is `/`
- joining `/` and `etc` gives `/etc`
- joining `/var` and `log` gives `/var/log`

This helper should not call the remote server.

## 9. UI Details

### 9.1 Host Sidebar

Keep the existing sidebar grouping:

- Favorites
- Recent
- My Hosts

Selecting a host should trigger remote loading for that host and local loading for that host's remembered local path.

### 9.2 Local File Panel

Toolbar:

- title: `Local`
- path text
- go-up icon button
- refresh icon button

List:

- folder icon for directories
- document icon for files
- directories sorted before files if the filesystem provider returns that order

### 9.3 Remote File Panel

Toolbar:

- title: selected host display name, or `Remote`
- path text
- go-up icon button
- refresh icon button

When no host is selected, show an empty state prompting host selection with concise wording.

### 9.4 Bottom Queue

Keep the current transfer queue placeholder. It should remain visually separated and not imply transfers are implemented.

## 10. Testing Strategy

### 10.1 Pure Logic Tests

Test:

- remote parent path helper
- local parent path helper
- display formatting for file size and dates if helpers are added

### 10.2 View Model Tests

Use fake `LocalFileSystem`, fake `RemoteFileSystem`, fake `CredentialStore`, and `HostSessionManager`.

Test:

- initial local path uses downloads fallback.
- selecting a host restores its current local/remote state.
- local refresh populates files.
- local directory open updates host local path.
- remote refresh populates files.
- remote directory open updates host remote path.
- failed remote load preserves path.
- host-key required and changed-key errors map to clear failed states.

### 10.3 Build Verification

Run:

```bash
swift test
swift build
```

Manual UI smoke can be done with `swift run wetrans` once the panel is implemented, but this spec does not require a full app bundle or UI automation.

## 11. Acceptance Criteria

- App main view uses three-pane browsing instead of file placeholders.
- User can browse local directories.
- User can select a saved host and load remote directory contents.
- User can enter local and remote folders.
- User can go up and refresh both panels.
- Switching hosts restores each host's last local and remote path.
- Remote load failure does not erase path state.
- Host-key required and changed-key errors are visible as structured user-facing panel errors.
- Transfer queue remains a placeholder.
- `swift test` passes.
- `swift build` passes.
