# wetrans Architecture Design

Status: MVP architecture baseline
Source PRD: `docs/prd.md`

## 1. Purpose

This document defines the first implementation architecture for wetrans, a native macOS SSH/SFTP remote file manager.

It translates the PRD into an engineering design that can support:

- Native macOS file-management interactions.
- Host creation from manual input or SSH Config generation.
- Local and remote directory browsing.
- Per-host browsing state.
- A global transfer queue.
- Secure credential and host-key handling.

The design favors deep modules with small interfaces. UI code should not know about libssh2, libssh, Keychain query dictionaries, JSON file paths, or transfer execution details.

## 2. Architecture Decisions

### 2.1 Platform Stack

wetrans should use:

```text
SwiftUI + AppKit
```

SwiftUI owns the application shell:

- App lifecycle.
- Main window composition.
- Sidebar container.
- Dialog presentation.
- Settings screens.
- Top-level state binding.

The MVP main window shell should not add an app-level top horizontal toolbar above the three-pane browser. Persistent global navigation belongs in the host sidebar; file operations belong to file-panel controls or context menus.

The current MVP renders the file panels in SwiftUI and uses narrow AppKit integrations for desktop services such as Finder reveal, pasteboard writes, and event modifier lookup.

AppKit remains the intended future owner for denser file-manager surfaces when the product needs higher-fidelity table behavior:

- Local file table.
- Remote file table.
- Directory outline behavior if introduced.
- Multi-selection.
- Drag and drop.
- Context menus.
- Keyboard focus and responder-chain behavior.
- Precise scrolling and column behavior.

SwiftUI and AppKit should communicate through narrow view models rather than letting table delegates mutate global app state directly.

### 2.2 Distribution Target

MVP targets Developer ID distribution outside the Mac App Store.

Reasons:

- SSH/SFTP and local file access are simpler without early sandbox constraints.
- Users are technical and likely comfortable with direct downloads during internal testing.
- App Store sandboxing can be revisited later with security-scoped bookmarks.

### 2.3 SSH Config Semantics

SSH Config is a host generation source, not a runtime dependency.

```text
Select alias -> run ssh -G alias -> build HostDraft -> save SavedHost -> connect from SavedHost
```

After save, the host is owned by wetrans. Changes to `~/.ssh/config` do not silently mutate saved hosts.

### 2.4 SFTP Implementation

The application should depend on a `RemoteFileSystem` interface, not directly on libssh2, libssh, or shell commands.

MVP implementation should start with a libssh2 spike and keep libssh as the fallback candidate.

The command-line `ssh` and `sftp` tools may be used for `ssh -G` config resolution and for local spike validation, but they should not be the production file-transfer engine.

## 3. Module Map

```text
SwiftUI App Shell
  -> AppState
  -> HostCatalog
  -> HostSessionManager
  -> TransferQueue

AppKit File Panels
  -> LocalFileBrowser
  -> RemoteBrowserViewModel
  -> HostSessionManager

Host Creation
  -> SSHConfigScanner
  -> SSHConfigResolver
  -> HostCatalog
  -> CredentialStore

Host Management UI
  -> HostCatalog
  -> CredentialStore

Remote Operations
  -> TransferQueue
  -> RemoteFileSystem
  -> CredentialStore
  -> TrustedHostStore

Persistence
  -> JSONDocumentStore
  -> CredentialStore
  -> TrustedHostStore
```

## 4. Core Modules

### 4.1 AppState

Owns top-level app coordination state.

Responsibilities:

- Current selected host ID.
- Current sidebar filter or group state.
- Transfer queue panel collapsed/expanded state.
- Dialog routing.
- App-wide error presentation.

Non-responsibilities:

- Reading or writing host JSON.
- Running SFTP operations.
- Parsing SSH Config.
- Direct Keychain access.

### 4.2 HostCatalog

Owns persisted host metadata.

Interface:

```swift
protocol HostCatalog {
    func load() throws -> [SavedHost]
    func save(_ host: SavedHost) throws
    func delete(hostId: UUID) throws
    func markConnected(hostId: UUID, at date: Date) throws
    func updatePaths(hostId: UUID, local: String?, remote: String?) throws
    func setFavorite(hostId: UUID, isFavorite: Bool) throws
}
```

Implementation notes:

- Backed by `hosts.json`.
- Writes should be atomic.
- Schema version should be stored at the document root.
- Deleting a host should also remove related credentials and runtime session state.

### 4.3 SSHConfigScanner

Owns SSH Config alias discovery.

Interface:

```swift
protocol SSHConfigScanner {
    func scanDefaultConfig() throws -> [SSHConfigAlias]
}
```

MVP behavior:

- Reads `~/.ssh/config`.
- Supports basic `Include`.
- Supports multiple aliases on one `Host` line.
- Filters wildcard aliases.
- Filters negated aliases.
- Ignores `Match` blocks for alias discovery.

### 4.4 SSHConfigResolver

Owns `ssh -G` execution and parsing.

Interface:

```swift
protocol SSHConfigResolver {
    func resolve(alias: String) async throws -> ResolvedSSHConfig
    func makeDraft(from resolved: ResolvedSSHConfig) -> HostDraft
}
```

Implementation notes:

- Run `/usr/bin/ssh -G <alias>` with a timeout.
- Parse key/value output into normalized fields.
- Preserve unsupported options as warnings.
- Do not save full SSH Config content.

### 4.5 CredentialStore

Owns Keychain access for secrets.

Interface:

```swift
protocol CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws
    func loadPassword(hostId: UUID) throws -> String?
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws
    func loadKeyPassphrase(hostId: UUID) throws -> String?
    func deleteCredentials(hostId: UUID) throws
}
```

Implementation notes:

- `hosts.json` must never contain passwords or private key passphrases.
- Keychain service names should be stable and app-specific.
- Keychain errors should be mapped to user-readable app errors.

### 4.6 TrustedHostStore

Owns trusted SSH host-key records.

Interface:

```swift
protocol TrustedHostStore {
    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey?
    func trust(_ key: TrustedHostKey) throws
    func recordVerification(hostId: UUID, at date: Date) throws
}
```

Implementation notes:

- Backed by `known_hosts.json`.
- Separate from OpenSSH's `known_hosts`.
- A host-key mismatch must block connection until the user explicitly decides.

### 4.7 RemoteFileSystem

Owns remote SFTP behavior behind a small interface.

Interface:

```swift
protocol RemoteFileSystem {
    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
    func upload(_ request: UploadRequest, in session: RemoteSession) async throws
    func download(_ request: DownloadRequest, in session: RemoteSession) async throws
}
```

Implementation notes:

- Concrete adapter may be `LibSSH2RemoteFileSystem` or `LibSSHRemoteFileSystem`.
- Session handles must not be shared concurrently unless the chosen library explicitly supports it.
- MVP concurrent transfers should use separate safe transfer contexts, such as separate SFTP sessions or library-supported independent handles.
- Transfer progress should be emitted through async streams or callback closures wrapped by higher-level Swift types.

### 4.8 HostSessionManager

Owns runtime host state and connection caching.

Responsibilities:

- Current local path per host.
- Current remote path per host.
- Runtime selection state.
- Live connection cache.
- Idle disconnect.
- Reconnect when switching back to a disconnected host.

Interface:

```swift
protocol HostSessionManager {
    func activate(host: SavedHost) async -> HostActivationResult
    func saveRuntimeState(for hostId: UUID, state: HostSessionState)
    func state(for hostId: UUID) -> HostSessionState?
    func disconnectIdleSessions(now: Date) async
}
```

### 4.9 TransferQueue

Owns global upload/download task execution.

Responsibilities:

- Enqueue transfer tasks.
- Run bounded concurrent transfers in MVP.
- Create one transfer task per selected file.
- Own progress and status updates.
- Support cancellation.
- Persist task summaries.
- Notify file panels when affected paths should refresh.

Interface:

```swift
protocol TransferQueue {
    func enqueueUpload(_ request: UploadRequest)
    func enqueueDownload(_ request: DownloadRequest)
    func cancel(taskId: UUID)
    func retry(taskId: UUID)
    var tasks: AsyncStream<[TransferTask]> { get }
}
```

MVP execution rule:

- Global concurrent queue with a default limit of 3 running tasks.
- Per-host queue with a default limit of 2 running tasks.
- No pause/resume.
- Running tasks interrupted by app quit are marked interrupted on next launch.

## 5. Data Flow

### 5.1 Host Creation From SSH Config

```text
Connect Host dialog
-> SSHConfigScanner.scanDefaultConfig()
-> user selects alias
-> SSHConfigResolver.resolve(alias)
-> HostDraft
-> user confirms or edits
-> HostCatalog.save(SavedHost)
-> CredentialStore saves any entered secret
-> HostSessionManager activates host
```

### 5.2 Manual Host Creation

```text
Manual Add dialog
-> HostDraft
-> validate required fields
-> HostCatalog.save(SavedHost)
-> CredentialStore saves password/passphrase
-> HostSessionManager activates host
```

### 5.3 Browse Remote Directory

```text
User selects host
-> HostSessionManager.activate(host)
-> RemoteFileSystem.connect if needed
-> TrustedHostStore validates host key
-> RemoteFileSystem.listDirectory(currentRemotePath)
-> RemoteBrowserViewModel publishes FileItem list
```

### 5.4 Upload

```text
User selects local files and clicks Upload
-> TransferQueue.enqueueUpload
-> queue creates one task per file
-> queue resolves host/session
-> RemoteFileSystem.upload
-> progress updates TransferTask
-> on success refresh affected remote directory
```

### 5.5 Download

```text
User selects remote files and clicks Download
-> TransferQueue.enqueueDownload
-> queue creates one task per file
-> queue resolves host/session
-> RemoteFileSystem.download
-> progress updates TransferTask
-> on success refresh affected local directory
```

## 6. Concurrency Model

Use Swift concurrency at app-module seams:

- UI updates on `MainActor`.
- SFTP work off the main actor.
- Transfer queue runs in its own actor.
- Host catalog writes should be serialized.
- Keychain calls should be wrapped so callers do not block UI paths.

Recommended actors:

```swift
actor TransferQueueActor
actor HostCatalogActor
actor HostSessionActor
```

AppKit table delegates should call view model methods and return quickly.

## 7. Error Model

Use typed domain errors rather than passing raw library errors directly through the UI.

Top-level categories:

- `HostCatalogError`
- `SSHConfigError`
- `CredentialError`
- `HostKeyError`
- `ConnectionError`
- `RemoteFileError`
- `TransferError`

Current implementation status:

- Core boundaries use typed errors such as `RemoteFileSystemError` and `CredentialStoreError`.
- UI surfaces map those errors to readable strings.
- Stable error codes, structured recovery suggestions, and expanded debug-detail objects remain future productization work.

## 8. Testing Strategy

### 8.1 Unit Tests

Prioritize:

- SSH Config alias filtering.
- `ssh -G` parser.
- Host JSON encoding/decoding and migrations.
- Transfer queue state transitions.
- Path restoration behavior.
- Error mapping.

### 8.2 Adapter Tests

Use fake adapters for:

- `CredentialStore`
- `RemoteFileSystem`
- `TrustedHostStore`
- `HostCatalog`

The app should be testable without a live SSH server for most behavior.

### 8.3 Integration Tests

Use local Docker OpenSSH-backed SFTP E2E as the default integration path. Keep fake adapters for most unit behavior, but require the real libssh2-backed path to prove SSH authentication, remote listing, upload, and download behavior without depending on an external public host.

Validate:

- Key authentication.
- Password authentication.
- Host-key trust and mismatch.
- List directory.
- Upload single file.
- Upload multiple files.
- Upload directory with nested child directories.
- Download single file.
- Download multiple files.
- Download directory with nested child directories.
- Cancellation.

### 8.4 E2E Script Layers

`scripts/e2e` is the default E2E entry point. It has two stable layers:

- Local Docker OpenSSH SFTP E2E through `RemoteFileSystemRealHostIntegrationTests` with temporary key and password credentials.
- Packaged app build/run smoke through the native `wetrans-e2e` Accessibility runner.

The app smoke verifies that the launched app exposes the main automation anchors:

- Connect Host.
- Local File Panel.
- Remote File Panel.
- Transfer Queue.

### 8.5 Opt-In Full UI Tests

Full UI scenarios remain opt-in because they depend on Accessibility permission, local SSH config state, and environment-provided host details. When `WETRANS_E2E_RUN_FULL=1` is set, the runner may cover:

- Launch app.
- Add manual host draft.
- Open SSH Config selection dialog with fixture data.
- Verify host switching restores paths.
- Verify transfer queue rows update.

## 9. Build and Project Layout

Recommended project layout:

```text
wetrans/
  UI/
  Domain/
  Persistence/
  SSHConfig/
  RemoteFileSystem/
  TransferQueue/
  Security/
wetransTests/
wetransE2E/
docs/
```

Keep domain and persistence modules usable from tests without launching the app.

## 10. Architecture Risks

### 10.1 SFTP Library Integration

Risk: C library packaging, signing, and async integration may take longer than expected.

Mitigation:

- Run a focused libssh2/libssh spike before full UI work.
- Keep the adapter behind `RemoteFileSystem`.
- Do not couple UI to library-specific handles.

### 10.2 SwiftUI/AppKit State Bridging

Risk: AppKit table delegates and SwiftUI state updates can become tangled.

Mitigation:

- Use view models as the seam.
- Keep AppKit wrappers small.
- Avoid direct global state mutation from delegates.

### 10.3 Host Key Semantics

Risk: Custom known-host handling can become insecure or confusing.

Mitigation:

- Treat unknown key, trusted key, and changed key as separate states.
- Block changed-key connections by default.
- Store explicit trust timestamps.

### 10.4 SSH Config Compatibility

Risk: Real user SSH configs are complex.

Mitigation:

- Generate hosts from `ssh -G`.
- Warn on unsupported resolved options.
- Make generated hosts editable.
- Treat generated hosts as independent saved hosts after creation.

## 11. References

- Apple Developer Documentation: AppKit integration for SwiftUI.
- Apple Developer Documentation: Keychain Services.
- libssh2 official documentation.
- libssh official documentation.
