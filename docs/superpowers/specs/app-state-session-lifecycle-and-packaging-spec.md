# App State, Session Lifecycle, and Packaging Spec

## 1. Purpose

This spec captures the implementation slice requested after the docs-vs-code gap review.

The slice has three goals:

- Align project documents with the current implementation where behavior is intentionally different from older PRD wording.
- Tighten host cleanup and credential lifecycle behavior around saved-host deletion and auth-type changes.
- Add a small app coordination state module, idle session disconnection, and an internal Developer ID packaging/notarization path.

## 2. Scope

### 2.1 Documentation Alignment

Update docs to match current implementation for:

- File transfer conflict behavior: current MVP transfer implementation writes to the requested destination path and does not yet provide a conflict prompt or conservative preflight block.
- File panel implementation: current file panels are SwiftUI-rendered file-list surfaces with narrow AppKit integrations for desktop services such as Finder reveal, pasteboard, and event modifier lookup.
- Error model: current errors use typed enums and user-readable string mapping, not a full stable-code/recovery/debug-detail object model.
- JSON persistence: current persistence uses schema-versioned JSON documents and temporary-file replacement, but does not yet implement migration backup files, explicit fsync, or bounded transfer-history pruning.

Remove docs that imply current or near-term support for favorite remote paths as a product feature. The model field may remain for compatibility, but user-facing documentation should not advertise the workflow.

### 2.2 Saved Host Cleanup

When a saved host is deleted from wetrans:

1. Remove it from `HostCatalog`.
2. Delete related Keychain credentials through `CredentialStore.deleteCredentials(hostId:)`.
3. Delete related trusted host keys through `TrustedHostStore.deleteKeys(hostId:)`.
4. Disconnect any live or pending runtime session for that host.

Deleting a generated host must still not mutate `~/.ssh/config`.

### 2.3 Auth-Type Credential Cleanup

When saving an edited host changes the auth type:

- Password -> SSH key: delete existing credentials for that host before saving the edited host. The current edit UI does not collect a new secret, so this prevents stale password reuse.
- SSH key -> password: delete existing credentials for that host before saving the edited host. The current edit UI does not collect a new password, so this prevents stale key passphrase reuse.

This slice does not add a secret-editing UI.

### 2.4 AppState

Add a small `AppState` module for top-level coordination state:

- Current selected host ID.
- Connect Host sheet presentation state.
- Transfer queue expanded/collapsed preference.
- Last app-level error message.

`AppState` should not access JSON, Keychain, SFTP, or SSH Config directly.

### 2.5 Idle Session Disconnect

`HostSessionManager` should expose an explicit idle disconnect API.

MVP behavior:

- Disconnect connected sessions whose `lastActiveAt` is older than a caller-provided timeout.
- Preserve runtime path state after disconnect.
- Ignore hosts that have no cached live session.
- Keep recently active sessions connected.

The app should call this periodically from the main browser view. The interval may be conservative and implementation-local.

### 2.6 Developer ID Packaging Path

Add a scriptable internal distribution path:

- Build `dist/wetrans.app`.
- Optionally code sign when a Developer ID identity is provided.
- Optionally create a zip artifact.
- Optionally submit for notarization when Apple credentials are provided.
- Staple notarization when submission succeeds.

The path must be safe on machines without signing credentials: it should explain what was skipped rather than failing unexpectedly.

## 3. Out of Scope

- Full AppKit table replacement.
- Favorite remote path UI/workflow.
- Full UI E2E enablement by default.
- OSLog/debug-detail surface expansion.
- Secret editing UI.

## 4. Acceptance Criteria

- Project docs no longer claim the MVP blocks destination conflicts before transfer.
- Project docs describe SwiftUI file panels with narrow AppKit integrations, matching the current implementation.
- Project docs no longer advertise favorite remote paths as a current/P1 workflow.
- Deleting a saved host calls `HostCatalog.delete`, `CredentialStore.deleteCredentials`, `TrustedHostStore.deleteKeys`, and runtime session disconnect.
- Saving an edited host with a changed auth type clears old credentials.
- `AppState` has tests for sheet presentation, selected host, transfer queue expansion, and app error state.
- `HostSessionManager` has tests for disconnecting only idle sessions and preserving paths.
- The app periodically asks `HostSessionManager` to disconnect idle sessions.
- Packaging script can build an app artifact without credentials and can opt into signing/notarization through environment variables.
