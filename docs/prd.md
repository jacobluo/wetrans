# wetrans PRD

Version: 0.3
Date: 2026-06-26
Audience: Product and engineering
Status: MVP baseline

## 1. Product Overview

### 1.1 Product Name

wetrans

### 1.2 Positioning

wetrans is a native macOS SSH/SFTP remote file manager for developers, operators, and technical users who frequently move files between a Mac and remote servers.

The core experience is:

```text
Select or add a host -> browse local and remote files -> upload/download -> manage transfer queue
```

wetrans does not try to replace a terminal. It focuses on making high-frequency remote file operations visual, predictable, and safe.

### 1.3 One-Line Description

Select a host from `~/.ssh/config` or add one manually, browse remote directories like Finder, and transfer files through a native three-pane Mac interface.

## 2. Product Principles

### 2.1 Do Not Show All SSH Config Hosts by Default

The left host sidebar must not automatically show every `Host` entry from the user's `~/.ssh/config`.

Reasons:

- SSH config files can contain many aliases, wildcards, jump hosts, old entries, and environment-specific hosts.
- Entries such as `Host *`, `Host prod-*`, and `Host !bad *` are not user-facing connection targets.
- Showing everything by default creates noise and can expose sensitive infrastructure names in the main UI.

SSH Config hosts appear only when the user clicks "Connect Host" and chooses "Select from SSH Config".

### 2.2 SSH Config Is a Host Creation Source, Not a Runtime Reference

wetrans does not continuously reference `~/.ssh/config` for saved hosts.

When a user selects an alias from SSH Config:

```text
User selects alias
-> wetrans runs ssh -G <alias>
-> wetrans resolves hostname, user, port, identity files, and supported options
-> wetrans creates a normal SavedHost record
-> future connections use the SavedHost data
```

After generation, the host behaves like a manually added host. The app may preserve `originSSHConfigAlias` for traceability, but the saved host does not require SSH Config to remain unchanged.

### 2.3 Persist User Configuration and Recoverable Experience

wetrans persists:

- Saved hosts
- Favorites
- Recent connections
- Last local path per host
- Last remote path per host
- Default remote path
- Transfer history needed for visible queue state

wetrans does not persist:

- Live SSH/SFTP connection objects
- Loading indicators
- Temporary selection state across app restarts
- Passwords or private key passphrases in local JSON files

Sensitive credentials must be stored in macOS Keychain.

### 2.4 Preserve Host Browsing State During Host Switching

Each host should retain its own local and remote browsing state while the app is running.

Example:

```text
dev:
  remote path: /home/ubuntu/project
  local path: ~/Projects/dev-upload

prod:
  remote path: /var/www
  local path: ~/Desktop/prod-config
```

When the user switches from `dev` to `prod` and back to `dev`, wetrans should restore `/home/ubuntu/project` rather than returning to the remote home directory.

### 2.5 Use a Three-Pane File Manager Layout

The main interface uses:

```text
Left: host sidebar
Middle: local file panel
Right: remote file panel
Bottom: global transfer queue
```

The main browsing window does not include an app-level horizontal toolbar above the three-pane workbench. Primary global navigation stays in the host sidebar, and file actions live inside the relevant file panel.

The goal is to feel familiar to users who understand Finder or dual-pane file managers.

### 2.6 Transfer Queue Is Global

Transfers do not belong to the currently selected host view. They belong to a global queue.

Users can:

- Start a download from `dev`
- Switch to `prod`
- Start an upload
- Return to `dev`

The transfer tasks continue independently of host switching.

## 3. Target Users

### 3.1 Developers

Developers are the primary users.

They often:

- Already use SSH
- Have `~/.ssh/config`
- Upload scripts, config files, build artifacts, and deployment packages
- Download logs, model files, database exports, and generated artifacts
- Know the command line but want file transfer to be more visual

### 3.2 Operations and DevOps Users

Operations users manage multiple servers and care about reliability.

They need:

- Clear host organization
- Fast switching between environments
- Directory browsing without recursive scanning
- Progress, failure reasons, retry, and cancellation
- Safe handling of credentials and host keys

### 3.3 Less Command-Line-Heavy Technical Users

These users can connect to servers but may not be comfortable with `scp`, `rsync`, or SFTP commands.

They need:

- Manual host setup
- Clear error messages
- A predictable upload/download model
- Native macOS interactions

## 4. Primary Use Cases

### 4.1 Create a Host from SSH Config

```text
Open wetrans
Click Connect Host
Choose Select from SSH Config
Search for dev
Select dev
wetrans runs ssh -G dev
wetrans shows the resolved host draft
User confirms or edits fields
wetrans saves a normal host record
wetrans connects and opens the default remote directory
```

### 4.2 Manually Add a Host

```text
Open wetrans
Click Connect Host
Choose Manual Add
Enter host, port, username, authentication method, and default path
Save and connect
wetrans stores normal fields locally
wetrans stores sensitive credentials in Keychain
```

### 4.3 Browse Local and Remote Directories

```text
Select a saved host
Middle panel shows local directory
Right panel shows remote directory
User navigates both panels independently
Each host remembers its last local and remote path
```

### 4.4 Upload a File

```text
Connect to dev
Open ~/Downloads locally
Open /home/ubuntu/project remotely
Select config.yaml
Upload to remote panel
Task enters global transfer queue
Progress is shown
Remote directory refreshes after success
```

### 4.5 Download a File

```text
Connect to prod
Open /var/log/nginx remotely
Open ~/Downloads/logs locally
Select access.log
Download to local panel
Task enters global transfer queue
Progress is shown
Local directory refreshes after success
```

### 4.6 Switch Hosts Without Losing Context

```text
Open dev at /home/ubuntu/project
Switch to prod and open /var/www
Switch back to dev
wetrans restores /home/ubuntu/project
```

### 4.7 Transfer Across Hosts

```text
Start downloading app.log from dev
Switch to prod
Start uploading config.yaml
Both tasks appear in the global transfer queue
Host switching does not cancel either task
```

## 5. Main Interface

### 5.1 Layout

```text
┌──────────────┬──────────────────────┬──────────────────────┐
│ Hosts        │ Local Files           │ Remote Files          │
│              │ ~/Downloads           │ /home/ubuntu/project  │
│ Favorites    │                      │                      │
│  dev         │ file.zip              │ app.py                │
│  prod        │ config.yaml           │ logs/                 │
│              │ build.tar.gz          │ config.yaml           │
│ Recent       │                      │                      │
│  gpu-a100    │                      │                      │
│  staging     │                      │                      │
│              │                      │                      │
│ My Hosts     │                      │                      │
│  test box    │                      │                      │
│              │                      │                      │
│ + Connect    │                      │                      │
├──────────────┴──────────────────────┴──────────────────────┤
│ Transfer Queue: 1 upload, 2 downloads, 1 failed    Expand   │
└──────────────────────────────────────────────────────────────┘
```

There is no additional top app toolbar above this workbench in the MVP layout.

### 5.2 Host Sidebar

The left sidebar shows only hosts the user has saved or connected to.

Groups:

- Favorites
- Recent
- My Hosts
- Connect Host

#### Favorites

Favorites can include manually added hosts and hosts generated from SSH Config.

#### Recent

Rules:

- Shows recently successful connections.
- Sorted by `lastConnectedAt` descending.
- Default maximum: 10 hosts.
- Reconnecting to the same host updates its timestamp.
- A recent host can be favorited.

#### My Hosts

Shows saved hosts. This includes manual hosts and SSH Config-generated hosts because both are persisted as normal host records.

### 5.3 Connect Host Dialog

The Connect Host screen has two entry points at the top:

```text
Manual Add
Enter host, username, port, authentication, default path, and note.

Select from SSH Config
Choose an alias from ~/.ssh/config, resolve it with ssh -G, then save it as a normal host.
```

Below those entry points, the same screen shows the existing saved-host management area:

- Search saved hosts.
- Select a saved host from a name-only list.
- Review host details, including source, default path, last path, auth type, and note.
- Edit non-secret host metadata.
- Favorite or unfavorite.
- Delete a saved host and clean related credentials.

## 6. Host Creation and Management

### 6.1 Manual Host Fields

| Field | Required | Description |
| --- | --- | --- |
| Display name | Yes | Name shown in the sidebar |
| Host / IP | Yes | Remote hostname or IP |
| Port | No | Defaults to 22 |
| Username | Yes | SSH username |
| Auth type | Yes | SSH key or password |
| Identity file | Conditional | Required for key authentication unless using a supported default |
| Password | Conditional | Required for password authentication |
| Private key passphrase | Conditional | Required if the key needs one |
| Default remote path | No | First path to open after connection |
| Note | No | User-defined description |

### 6.2 SSH Config Host Generation

#### Flow

```text
Click Connect Host
Choose Select from SSH Config
wetrans reads ~/.ssh/config
wetrans shows supported Host aliases
User selects an alias
wetrans runs ssh -G <alias>
wetrans creates a HostDraft from resolved config
User confirms or edits the draft
wetrans saves a SavedHost
```

#### Host Display Rules

Show:

```text
Host dev
Host prod staging
```

Do not show:

```text
Host *
Host prod-*
Host ?
Host !bad *
```

MVP rules:

- Support plain Host aliases.
- Support multiple aliases on one Host line.
- Support basic Include expansion.
- Filter wildcard aliases.
- Filter negated aliases.
- Ignore unsupported `Match` behavior during alias scanning.

#### Resolved Field Mapping

`ssh -G <alias>` may populate:

- `hostname`
- `user`
- `port`
- `identityfile`
- `proxyjump`
- `proxycommand`

MVP saves only supported connection fields. Unsupported advanced fields should produce a clear warning before saving or connecting.

### 6.3 Saved Host Persistence

Normal host data is stored under:

```text
~/Library/Application Support/wetrans/hosts.json
```

Sensitive values are stored in Keychain:

```text
service: wetrans.ssh.password
account: <hostId>

service: wetrans.ssh.keyPassphrase
account: <hostId>
```

### 6.4 Saved Host Independence

Generated hosts are normal saved hosts after creation. wetrans does not refresh saved hosts from SSH Config after they have been created.

## 7. Browsing State

### 7.1 Persisted Per-Host State

These fields persist across app restarts:

- Last remote path
- Last local path
- Default remote path
- Last connected time
- Favorite state

### 7.2 Runtime Per-Host State

These fields are retained while the app is running:

- Current remote path
- Current local path
- Expanded remote directories
- Selected remote files
- Selected local files
- Remote scroll position
- Local scroll position
- Current loading state
- Current error state

MVP can persist only paths and favorite metadata. Runtime UI state can remain in memory.

### 7.3 Host Switching Behavior

When the user selects another host:

```text
1. Save current host browsing state.
2. Switch panels to the target host.
3. If target host has a live connection, restore its remote path.
4. If target host is disconnected, reconnect.
5. On success, restore the last remote path.
6. On failure, show an error and keep the last known state.
```

### 7.4 Connection Cache

MVP recommendation:

- Keep the current host connected.
- Keep the 2-3 most recently used hosts connected briefly.
- Disconnect idle sessions after 10-15 minutes.
- Preserve UI state after disconnect.
- Reconnect when the user switches back.

## 8. Local File Panel

### 8.1 Default Path Priority

```text
Host-specific last local path
User default download directory
~/Downloads
User home directory
```

### 8.2 MVP Features

- Browse local directories.
- Go to parent directory.
- Refresh.
- Select multiple files.
- Show file name, size, type, and modified time.
- Upload selected files to the current remote directory.
- Reveal selected file in Finder.

### 8.3 P1 Features

- Drag local files to remote panel.
- Context menu upload.
- Quick jump to default download directory.

## 9. Remote File Panel

### 9.1 Default Path Priority

```text
Host-specific last remote path
Host default remote path
Remote home directory
/
```

### 9.2 MVP Features

- Browse remote directories.
- Enter folders.
- Go to parent directory.
- Refresh current directory.
- Show file name, size, modified time, and permissions.
- Select multiple files.
- Download selected files to the current local directory.
- Copy remote path.
- Show loading and error states.

### 9.3 Lazy Loading Rules

Remote browsing must not recursively scan the server.

Rules:

- Load only the current directory after connection.
- Load child directories only when the user opens them.
- Refresh only the current path.
- Do not prefetch the whole remote tree.

### 9.4 P1 Remote Operations

- Drag remote files to local panel.
- Rename.
- Delete.
- Create directory.
- Change permissions.
- Rich context menu.

## 10. Upload and Download

### 10.1 Upload

#### MVP Entry Points

- Upload toolbar button.
- Upload selected local files to current remote directory.

#### MVP Rules

- Show progress.
- Allow cancel.
- Refresh remote directory after success.
- Show understandable errors.

#### P1 Rules

- Drag local files into remote panel.
- File conflict handling.
- Retry failed transfers.

### 10.2 Download

#### MVP Entry Points

- Download toolbar button.
- Download selected remote files to current local directory.

#### MVP Rules

- Show progress.
- Allow cancel.
- Refresh local directory after success.
- Show understandable errors.

#### P1 Rules

- Drag remote files into local panel.
- File conflict handling.
- Retry failed transfers.

### 10.3 File Conflict Handling

The current MVP transfer implementation writes to the requested destination path and does not yet present a conflict prompt or preflight block for existing files. Users should choose destination directories with that behavior in mind during internal testing.

P1 should add explicit conflict handling:

```text
Destination already contains config.yaml.

Overwrite
Skip
Rename
Apply to remaining conflicts
```

## 11. Global Transfer Queue

### 11.1 Purpose

The transfer queue is the global task center for uploads and downloads across all hosts.

### 11.2 Location

The queue sits at the bottom of the main window.

Collapsed:

```text
Transfer Queue: 1 upload, 2 downloads, 1 failed    Expand
```

Expanded:

```text
File | Host | Direction | Progress | Speed | Status | Action
```

### 11.3 Task Fields

Each transfer task includes:

- Task ID
- Host ID
- Host display name
- Direction: upload or download
- Local path
- Remote path
- File name
- File size
- Transferred bytes
- Progress
- Speed
- Status
- Error message
- Created time
- Started time
- Completed time

### 11.4 Task Statuses

```text
Pending
Running
Succeeded
Failed
Cancelled
Paused
```

MVP does not need pause/resume behavior. `Paused` can be reserved for future use.

### 11.5 Execution Strategy

MVP:

- Global concurrent transfer with a default limit of 3 running tasks.
- The same host runs up to 2 transfers at a time by default.
- Other tasks wait in the global queue.

P1:

- User-configurable global concurrency limit.
- User-configurable per-host concurrency limit.

### 11.6 Host Switching Behavior

Rules:

- Switching hosts does not interrupt transfers.
- Transfer tasks continue in the global queue.
- On completion, wetrans refreshes the affected directory state.
- If the user is viewing the affected directory, the UI updates immediately.
- If not, the next visit should show the latest state.

### 11.7 Failed Task Management

Failed tasks remain visible.

Supported actions:

- Retry
- Delete
- View error
- Copy error detail

Common errors:

- Permission denied
- Connection interrupted
- Local directory missing
- Remote file missing
- Disk full
- Authentication failed
- Host key mismatch

## 12. Data Model

### 12.1 HostSource

```swift
enum HostSource: String, Codable {
    case manual
    case sshConfigGenerated
}
```

### 12.2 AuthType

```swift
enum AuthType: String, Codable {
    case password
    case sshKey
}
```

### 12.3 SavedHost

```swift
struct SavedHost: Identifiable, Codable {
    let id: UUID
    var source: HostSource

    var displayName: String
    var hostname: String
    var port: Int
    var username: String
    var authType: AuthType
    var identityFile: String?

    var isFavorite: Bool
    var lastConnectedAt: Date?
    var lastRemotePath: String?
    var lastLocalPath: String?
    var defaultRemotePath: String?
    var favoriteRemotePaths: [String]

    var originSSHConfigAlias: String?
    var resolvedAt: Date?
    var note: String?
}
```

### 12.4 HostSessionState

```swift
struct HostSessionState {
    let hostId: UUID

    var isConnected: Bool
    var lastActiveAt: Date?

    var currentRemotePath: String
    var currentLocalPath: String

    var expandedRemotePaths: Set<String>
    var selectedRemotePaths: Set<String>
    var selectedLocalPaths: Set<String>

    var remoteScrollPosition: Double?
    var localScrollPosition: Double?
}
```

### 12.5 ResolvedSSHConfig

```swift
struct ResolvedSSHConfig {
    let alias: String
    let hostname: String
    let user: String?
    let port: Int
    let identityFiles: [String]
    let proxyJump: String?
    let proxyCommand: String?
}
```

### 12.6 FileItem

```swift
struct FileItem: Identifiable {
    let id: String
    let name: String
    let path: String
    let isDirectory: Bool
    let isSymlink: Bool
    let size: UInt64?
    let modifiedAt: Date?
    let permissions: String?
}
```

### 12.7 TransferTask

```swift
enum TransferDirection: String, Codable {
    case upload
    case download
}

enum TransferStatus: String, Codable {
    case pending
    case running
    case succeeded
    case failed
    case cancelled
    case paused
}

struct TransferTask: Identifiable, Codable {
    let id: UUID
    let hostId: UUID
    let hostDisplayName: String

    let direction: TransferDirection
    let localPath: String
    let remotePath: String

    let fileName: String
    let totalBytes: UInt64?
    var transferredBytes: UInt64
    var progress: Double

    var speedBytesPerSecond: UInt64?
    var status: TransferStatus
    var errorMessage: String?

    let createdAt: Date
    var startedAt: Date?
    var completedAt: Date?
}
```

## 13. Technical Architecture

### 13.1 Client Technology

Recommended stack:

```text
SwiftUI + AppKit
```

SwiftUI should own:

- Window shell
- Top-level layout
- Dialogs
- State binding
- Settings views

AppKit should own:

- Future high-fidelity file tables.
- Future outline/list interactions.
- Future drag and drop after directory transfer hardening and E2E default-path coverage are stable.
- Future Finder-grade multi-select.
- Context menus and desktop integrations where SwiftUI benefits from AppKit bridges.
- Future precise keyboard behavior.

The current MVP file panels are SwiftUI-rendered list surfaces with narrow AppKit integrations for Finder reveal, pasteboard, and modifier-event lookup.

### 13.2 Core Modules

#### HostCatalog

Owns saved hosts, favorites, recent connections, and persisted host metadata.

Interface responsibilities:

- Load hosts.
- Save hosts.
- Create manual host.
- Create host from SSH Config draft.
- Update favorite status.
- Update last paths and last connection time.

#### SSHConfigScanner

Scans SSH Config files and returns selectable aliases.

Interface responsibilities:

- Read `~/.ssh/config`.
- Expand basic Include entries.
- Extract plain aliases.
- Filter wildcard and negated aliases.

#### SSHConfigResolver

Turns a selected alias into a host draft.

Interface responsibilities:

- Run `ssh -G <alias>`.
- Parse resolved config.
- Map supported values to `HostDraft`.
- Report unsupported options clearly.

#### CredentialStore

Owns Keychain access.

Interface responsibilities:

- Save password for host ID.
- Save key passphrase for host ID.
- Retrieve credential when connecting.
- Delete credentials when host is removed.

#### RemoteFileSystem

Owns SFTP operations behind a small interface.

Interface responsibilities:

- Connect.
- Disconnect.
- List directory.
- Upload file.
- Download file.
- Cancel transfer.
- Report progress.

The UI and transfer queue should not depend directly on libssh, libssh2, or any concrete SSH implementation.

#### HostSessionManager

Owns runtime host browsing state and connection cache.

Interface responsibilities:

- Save current host runtime state.
- Restore target host state.
- Reconnect if needed.
- Expire idle sessions.

#### TransferQueue

Owns global upload/download execution.

Interface responsibilities:

- Enqueue upload.
- Enqueue download.
- Run bounded concurrent queue in MVP.
- Track progress.
- Cancel running or pending task.
- Mark success or failure.
- Refresh affected file panels through notifications or state updates.

### 13.3 SFTP Implementation Direction

MVP should use a native SFTP library through a Swift adapter.

Recommended evaluation order:

1. libssh2
2. libssh
3. OpenSSH command-line fallback for limited prototype use only

The production interface should hide the implementation choice behind `RemoteFileSystem`.

### 13.4 Unsupported SSH Features in MVP

MVP should detect or warn for:

- Complex `ProxyCommand`
- `ProxyJump`
- SSH Agent-only flows
- Keyboard-interactive authentication
- `Match` blocks
- Host-specific scripts or unusual SSH config directives

The user-facing message should be clear:

```text
This host uses SSH options that wetrans does not support yet. You can edit the generated host settings manually or connect from Terminal.
```

## 14. Security Requirements

### 14.1 Credential Storage

wetrans must never store these in local JSON:

- SSH password
- Private key passphrase
- Tokens

Sensitive values must be stored in macOS Keychain.

### 14.2 Host Key Verification

First connection to a host must show the host key fingerprint:

```text
First connection to this host. Confirm the host key fingerprint.

Trust and Continue
Cancel
```

If the host key changes, wetrans must show a strong warning:

```text
The remote host fingerprint changed. This may indicate a security risk.
```

The user must explicitly decide whether to trust the new key.

### 14.3 SSH Config Handling

wetrans may read SSH Config files for alias selection and generation.

wetrans must not:

- Automatically expose all aliases in the sidebar.
- Silently execute complex unsupported ProxyCommand behavior.
- Silently overwrite a saved host from changed SSH Config.

## 15. Error Handling

### 15.1 Error Message Principles

Error messages should:

- Use plain language.
- Explain what happened.
- Suggest a next step.
- Avoid raw stack traces by default.
- Use typed domain errors and focused string mapping. A full stable-code/recovery/debug-detail object model is not implemented yet.

### 15.2 Common Errors

| Scenario | Message |
| --- | --- |
| SSH Config missing | `~/.ssh/config was not found. You can add a host manually.` |
| Alias cannot be resolved | `wetrans could not resolve this SSH Config host.` |
| Unsupported SSH option | `This host uses SSH options wetrans does not support yet.` |
| Connection timeout | `Connection timed out. Check the network or host address.` |
| Authentication failed | `Authentication failed. Check the username, password, or SSH key.` |
| Permission denied | `This user does not have permission to access the file or directory.` |
| Local path missing | `The local folder no longer exists.` |
| Remote path missing | `The remote file or folder no longer exists.` |
| Upload failed | `Upload failed. Check the remote directory permissions.` |
| Download failed | `Download failed. Check the local folder permissions.` |
| Transfer interrupted | `The connection was interrupted. You can retry the task.` |
| Host key changed | `The remote host fingerprint changed. Verify this host before continuing.` |

## 16. MVP Scope

### 16.1 P0 Must-Have Features

- Native macOS app shell.
- Three-pane layout.
- Host sidebar with Favorites, Recent, My Hosts, and Connect Host.
- Manual host creation.
- SSH Config alias selection.
- `ssh -G` host generation.
- SavedHost persistence.
- Keychain credential storage.
- Basic host key verification.
- SFTP connection.
- Remote directory listing.
- Local directory listing.
- Host switching with path preservation.
- Multi-file upload.
- Multi-file download.
- Global concurrent transfer queue.
- Transfer progress.
- Transfer cancellation.
- Basic transfer failure messages.
- Recent connection tracking.
- Favorite host toggle.

### 16.2 Explicit MVP Non-Goals

- Folder upload.
- Folder download.
- Recursive remote scanning.
- Pause/resume transfer.
- Resume interrupted transfer.
- Directory sync.
- Remote file editing.
- Built-in terminal.
- Multi-tab browsing.
- Full ProxyJump support.
- Full ProxyCommand support.
- SSH Agent support.
- Keyboard-interactive support.
- Multi-protocol support.

### 16.3 P1 Features

- Directory upload/download.
- File conflict handling.
- Retry failed transfers.
- Copy remote path.
- Context menus.

### 16.4 P2 Features

- Pause/resume.
- Resumable transfers.
- Directory sync.
- Remote file editing and upload back.
- ProxyJump support.
- SSH Agent support.
- Built-in terminal panel.
- Multi-tab browsing.
- Remote search.
- Additional protocols.

## 17. MVP Acceptance Criteria

### 17.1 Host Management

- User can manually add a host.
- User can select an alias from SSH Config.
- SSH Config selection generates a normal saved host.
- Saved hosts persist after app restart.
- Passwords and passphrases do not appear in local JSON files.
- Favorites persist after app restart.
- Recent connections update after successful connection.

### 17.2 Browsing

- User can browse local directories.
- User can browse remote directories after connecting.
- Remote directory loading has a loading state.
- Remote directory loading failure shows a useful error.
- wetrans does not recursively load the full remote tree.
- Switching hosts preserves each host's last local and remote path.
- Reconnecting to a host restores its last remote path when possible.

### 17.3 Transfers

- User can upload multiple local files to the current remote directory.
- User can download multiple remote files to the current local directory.
- Upload and download tasks appear in the same global transfer queue.
- Queue shows host, file, direction, progress, and status.
- User can cancel a pending or running task.
- Failed task shows an understandable error.
- Host switching does not interrupt a running transfer.
- Completed upload refreshes the affected remote directory.
- Completed download refreshes the affected local directory.

### 17.4 Security

- First connection asks the user to trust the host key.
- Host key changes produce a strong warning.
- Sensitive credentials are stored in Keychain.
- Unsupported SSH options are not silently executed.

## 18. Success Metrics

### 18.1 Product Metrics

- First connection success rate.
- SSH Config alias generation success rate.
- Manual host creation completion rate.
- Upload success rate.
- Download success rate.
- Average steps to complete first upload.
- Average steps to complete first download.
- Transfer retry success rate.
- Favorite host usage.
- Recent host usage.
- One-week repeat usage.

### 18.2 MVP Quality Metrics

- User can complete first connection within 1 minute if credentials are ready.
- User can create a host from SSH Config in 3 main actions.
- User can upload or download from the three-pane layout without using Terminal.
- Host path state survives host switching.
- Transfer tasks survive host switching.
- No sensitive credentials are stored in plaintext config files.
- Failed transfers provide actionable feedback.

## 19. Development Milestones

### Milestone 1: Project Foundation and Host Management

Scope:

- macOS app scaffold.
- App identity as wetrans.
- Host data model.
- Local persistence.
- Keychain wrapper.
- Manual host form.
- SSH Config scanner.
- `ssh -G` resolver.
- Host generation from SSH Config.

Outcome:

- User can create, save, favorite, and reopen hosts.

### Milestone 2: Connection and File Browsing

Scope:

- SFTP adapter.
- Host key verification.
- Connection lifecycle.
- Local file panel.
- Remote file panel.
- Lazy remote listing.
- Host switching state.

Outcome:

- User can connect to a host and browse local/remote directories.

### Milestone 3: Transfers and Queue

Scope:

- Global concurrent queue with a default limit of 3 running tasks.
- Progress tracking.
- Cancellation.
- Completion refresh.
- Failure messages.

Outcome:

- User can reliably upload and download multiple selected files with bounded concurrency.

### Milestone 4: Productization for Internal Testing

Scope:

- Directory upload/download.
- Context menus.
- Better empty/loading/error states.
- Logs and debug details.
- App signing and packaging.
- Default E2E path covering real-host SFTP connect/list/upload/download and packaged app smoke.
- Basic onboarding copy.

Outcome:

- wetrans is ready for internal testing by technical users.

## 20. Key Product Decisions

### Decision 1: Product Name Is wetrans

The app name is wetrans.

### Decision 2: SSH Config Hosts Are Generated, Not Referenced

Selecting from SSH Config creates a normal saved host. wetrans does not rely on SSH Config at runtime for that saved host.

### Decision 3: Do Not Show All SSH Config Hosts by Default

The main sidebar only shows saved or used hosts.

### Decision 4: Use Three-Pane Layout

The primary app surface is host sidebar, local file panel, remote file panel, and global transfer queue.

### Decision 5: Preserve Per-Host Paths

Each host keeps its own local and remote path state.

### Decision 6: Use a Global Transfer Queue

Transfer tasks continue across host switching and are not tied to the current remote panel.

### Decision 7: Persist Host Data, Store Secrets in Keychain

Normal host metadata is saved locally. Sensitive credentials are stored in macOS Keychain.

### Decision 8: MVP Focuses on SFTP File Management

The first release focuses on host creation, browsing, multi-file upload/download, and queue management. Terminal, sync, and advanced SSH features come later.

## 21. Implementation Planning Defaults

These defaults make the PRD executable while still allowing implementation planning to refine details.

### 21.1 SFTP Library Selection

MVP should begin with a short technical spike comparing libssh2 and libssh.

Default recommendation:

- Try libssh2 first because it is focused on client SSH/SFTP use cases and has a relatively small surface.
- Keep `RemoteFileSystem` as the only interface exposed to the app so the concrete library can change without affecting UI, host management, or transfer queue code.

### 21.2 MVP Authentication Support

MVP should support both:

- Password authentication
- SSH key authentication with optional private key passphrase

Passwords and private key passphrases must be stored in Keychain.

### 21.3 Transfer Task Persistence

MVP should persist completed, failed, and cancelled task summaries so users can see recent transfer results after relaunch.

MVP should not attempt to resume running tasks after app restart. Any task that was running when the app quit should be marked as failed or interrupted on next launch with a retry option.

### 21.4 Transfer Concurrency

MVP should support multi-file upload and download by creating one transfer task per selected file.

Default limits:

- Global running tasks: 3
- Running tasks per host: 2

This gives users visible parallelism while avoiding unsafe sharing of a single SSH/SFTP session handle. P1 can make these limits configurable after the core transfer behavior is stable.

### 21.5 Host Key Persistence

MVP should persist trusted host key records under Application Support, separate from `hosts.json`.

Suggested path:

```text
~/Library/Application Support/wetrans/known_hosts.json
```

Each record should include:

- Host ID
- Hostname
- Port
- Key type
- Fingerprint
- First trusted time
- Last verified time

### 21.6 Editing Generated Hosts

Hosts generated from SSH Config should be editable before first save and after save.

`originSSHConfigAlias` and `resolvedAt` are metadata, not locks. Users can change display name, username, port, identity file, default remote path, note, and authentication method after generation.

### 21.7 Distribution and File Access

MVP should target Developer ID distribution outside the Mac App Store first. This keeps local file access and SSH/SFTP integration simpler during early development.

If App Store distribution is considered later, wetrans should revisit sandboxing, security-scoped bookmarks, and user-selected folder access.

## 22. Summary

wetrans is a native macOS remote file manager centered on SSH/SFTP workflows.

Its core value is:

```text
Choose or add a host
Browse local and remote files side by side
Upload and download through a global queue
Switch hosts without losing context
```

The most important MVP decisions are:

- SSH Config is a host generation source, not a runtime dependency.
- Saved host data persists locally.
- Sensitive credentials live in Keychain.
- Three-pane browsing and global transfers define the main product experience.
- The first version focuses on reliable multi-file SFTP transfer with bounded concurrency before advanced features.
