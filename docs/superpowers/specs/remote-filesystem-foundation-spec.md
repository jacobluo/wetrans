# Remote File System Foundation Spec

Status: Draft for review
Parent PRD: `docs/prd.md`
Related docs:

- `docs/architecture-design.md`
- `docs/data-model.md`
- `docs/implementation-plan.md`
- `docs/superpowers/specs/credential-and-host-key-security-spec.md`

## 1. Purpose

This spec defines the module foundation for local and remote file browsing in wetrans.

It is the first slice of M6: Local and Remote Browsing. It creates testable contracts and session coordination before introducing AppKit file panels or a real libssh2 adapter.

The feature slice ends when wetrans can:

- List local directories through a `LocalFileSystem` adapter.
- Build a connection request from a `SavedHost`.
- Use a `RemoteFileSystem` protocol to connect, disconnect, and list a remote directory.
- Preserve per-host local and remote browsing paths in `HostSessionManager`.

## 2. User Value

This slice does not expose the final file-browser UI yet, but it makes the next UI slice straightforward.

After this spec, the app has a stable browsing core:

- UI can ask for local files without knowing `FileManager` details.
- UI can ask for remote files without knowing libssh2/libssh details.
- Host switching can preserve per-host local and remote paths.
- Future SFTP code plugs into `RemoteFileSystem` without changing UI view models.

## 3. Scope

### 3.1 In Scope

- `LocalFileSystem` protocol.
- `FileManagerLocalFileSystem` implementation.
- Local directory listing mapped to existing `FileItem`.
- Local listing errors mapped to app-level errors.
- `ConnectionSpec` built from `SavedHost` and credential values.
- `RemoteFileSystem` protocol.
- `RemoteSession` value model.
- `RemoteFileSystemError` cases needed by callers.
- `MockRemoteFileSystem` for tests and early UI development.
- `HostSessionManager`.
- Per-host current local path.
- Per-host current remote path.
- Connect-on-demand behavior.
- Remote directory listing through `RemoteFileSystem`.
- Disconnect behavior.
- Unit tests for local listing, connection spec building, remote mock behavior, and session state preservation.

### 3.2 Out of Scope

- Real libssh2 or libssh implementation.
- Real SSH authentication.
- Real host-key extraction.
- Unknown-host or changed-host-key UI.
- AppKit file panels.
- Drag and drop.
- Upload and download.
- Transfer queue.
- Recursive remote directory loading.
- Remote file mutation such as delete, rename, chmod, or mkdir.

## 4. Product Decisions

### 4.1 Protocol First, Adapter Later

The UI and session manager depend on protocols:

```swift
protocol LocalFileSystem
protocol RemoteFileSystem
```

The production remote adapter can later be `LibSSH2RemoteFileSystem` or `LibSSHRemoteFileSystem`.

This keeps the browsing UI from depending on C library details and lets tests use a deterministic mock remote filesystem.

### 4.2 One Remote Session Per Host State

`HostSessionManager` owns runtime session state per `hostId`.

For MVP browsing:

- A host gets a session when the user first requests remote listing.
- Switching away from a host does not erase its current paths.
- Disconnect clears the live remote session but preserves current paths.

Connection caching timeouts are deferred to the real connection spec.

### 4.3 Path Defaults Stay Deterministic

Local path default order:

```text
SavedHost.lastLocalPath
~/Downloads
home directory
```

Remote path default order:

```text
SavedHost.lastRemotePath
SavedHost.defaultRemotePath
~
```

The real SFTP adapter may later resolve `~` to the remote home directory after connection.

### 4.4 No Recursive Remote Scans

This foundation only supports:

```swift
listDirectory(path)
```

It does not recursively scan subdirectories. UI or later tree behavior must request each directory explicitly.

## 5. Module Design

### 5.1 LocalFileSystem

```swift
protocol LocalFileSystem {
    func listDirectory(_ path: String) throws -> [FileItem]
}
```

`FileManagerLocalFileSystem` responsibilities:

- Read a single local directory.
- Map entries to `FileItem`.
- Sort directories before files, then localized case-insensitive name.
- Include file size and modification date when available.
- Mark directories.
- Mark symlinks.

Non-responsibilities:

- Recursive traversal.
- Finder reveal.
- Drag and drop.
- File mutations.

### 5.2 ConnectionSpec

```swift
struct ConnectionSpec: Equatable {
    let hostId: UUID
    let displayName: String
    let hostname: String
    let port: Int
    let username: String
    let auth: ConnectionAuth
    let defaultRemotePath: String
}

enum ConnectionAuth: Equatable {
    case password(String?)
    case sshKey(identityFile: String, passphrase: String?)
}
```

Rules:

- Password hosts use `CredentialStore.loadPassword`.
- SSH key hosts use `identityFile` from `SavedHost` and `CredentialStore.loadKeyPassphrase`.
- Missing password is allowed; later connection UI can prompt.
- Missing identity file for SSH key hosts is an error.
- `defaultRemotePath` uses the path default rules.

### 5.3 RemoteFileSystem

```swift
protocol RemoteFileSystem {
    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
}
```

`RemoteSession`:

```swift
struct RemoteSession: Identifiable, Equatable {
    let id: UUID
    let hostId: UUID
    let displayName: String
    let connectedAt: Date
}
```

The real adapter will later attach C library handles behind private implementation objects. This model intentionally exposes only stable app-level identity.

### 5.4 MockRemoteFileSystem

`MockRemoteFileSystem` is a test and early UI adapter.

Responsibilities:

- Record connection specs.
- Return deterministic directory listings by path.
- Throw configured errors.
- Track disconnect calls.

It is not production code.

### 5.5 HostSessionManager

Responsibilities:

- Store `HostSessionState` by `hostId`.
- Initialize state from `SavedHost`.
- Build `ConnectionSpec`.
- Connect on demand through `RemoteFileSystem`.
- List current remote directory.
- Update current local and remote paths.
- Preserve paths when switching hosts.
- Disconnect a host while keeping path state.

Non-responsibilities:

- UI presentation.
- Credential prompting.
- Host-key verification UI.
- Transfer execution.
- Connection cache eviction timers.

## 6. Data Flow

### 6.1 Local Listing

```text
UI/ViewModel
-> LocalFileSystem.listDirectory(path)
-> [FileItem]
```

The caller decides loading and error presentation.

### 6.2 Remote Listing

```text
UI/ViewModel
-> HostSessionManager.listRemoteDirectory(for: host)
-> build ConnectionSpec if needed
-> RemoteFileSystem.connect(spec) if no live session
-> RemoteFileSystem.listDirectory(currentRemotePath, session)
-> [FileItem]
```

### 6.3 Host Switching

```text
dev state currentRemotePath = /home/ubuntu/project
prod state currentRemotePath = /var/www
switch back to dev
-> state still points at /home/ubuntu/project
```

This spec implements the state behavior. Later UI specs will bind sidebar selection to this manager.

## 7. Error Handling

### 7.1 LocalFileSystemError

Recommended cases:

```swift
enum LocalFileSystemError: Error, Equatable {
    case notDirectory(String)
    case cannotRead(String)
}
```

Foundation errors may be wrapped or propagated if they provide useful detail. User-facing strings are not part of this spec.

### 7.2 ConnectionSpecError

Recommended cases:

```swift
enum ConnectionSpecError: Error, Equatable {
    case missingIdentityFile(hostId: UUID)
}
```

Missing password is not an error in this slice.

### 7.3 RemoteFileSystemError

Recommended cases:

```swift
enum RemoteFileSystemError: Error, Equatable {
    case connectionFailed(String)
    case disconnected
    case notDirectory(String)
    case permissionDenied(String)
}
```

Real libssh2/libssh errors will later map into these or more specific app errors.

## 8. Testing Requirements

Local file system tests:

- Lists files and directories from a temporary directory.
- Sorts directories before files.
- Includes file size for regular files.
- Throws for a path that is not a directory.

Connection spec tests:

- Password host includes password from `CredentialStore`.
- Password host allows missing password.
- SSH key host includes identity file and passphrase.
- SSH key host without identity file throws.
- Remote path defaults to last remote path, then default remote path, then `~`.

Remote/session tests:

- First remote listing connects then lists.
- Second listing for same host reuses session.
- Updating remote path changes the listed path.
- Switching between hosts preserves each host path.
- Disconnect clears live session but preserves paths.

## 9. Acceptance Criteria

- `LocalFileSystem` and `FileManagerLocalFileSystem` exist and are tested.
- `ConnectionSpec` can be built from `SavedHost` and `CredentialStore`.
- `RemoteFileSystem` and `RemoteSession` exist.
- `MockRemoteFileSystem` supports deterministic tests.
- `HostSessionManager` preserves per-host local and remote paths.
- `HostSessionManager` connects on demand and reuses live sessions.
- No remote recursive scanning is introduced.
- `swift test` passes.

## 10. Future Work

- Real libssh2 adapter.
- Host-key extraction and verification inside real connection flow.
- AppKit local file panel.
- AppKit remote file panel.
- Sidebar selection wiring into `HostSessionManager`.
- Transfer queue integration.

