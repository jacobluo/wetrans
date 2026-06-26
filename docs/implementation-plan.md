# wetrans Implementation Plan

> **For agentic workers:** Use this as the canonical overall implementation plan. For a milestone-level execution plan, create or use a focused Superpowers spec under `docs/superpowers/specs/` first, then produce a task-level execution plan from that spec.

**Goal:** Build the MVP of wetrans: a native macOS SSH/SFTP file manager with saved hosts, SSH Config host generation, local/remote browsing, and bounded concurrent multi-file transfers.

**Architecture:** The app uses SwiftUI for the shell and AppKit for dense file-table interactions. Core behavior is isolated behind deep modules: host catalog, SSH config scanner/resolver, credential store, trusted host store, remote file system, host session manager, and transfer queue.

**Tech Stack:** SwiftUI, AppKit, Swift concurrency, Keychain Services, JSON persistence under Application Support, libssh2 spike first with libssh fallback.

---

## 1. Source Documents

- Product PRD: `docs/prd.md`
- Architecture design: `docs/architecture-design.md`
- Technical selection: `docs/technical-selection.md`
- Data model: `docs/data-model.md`
- Agent guide: `AGENTS.md`

## 2. Implementation Principles

- Build native macOS only.
- Keep UI independent from libssh2/libssh and Keychain details.
- Prefer small, testable modules with clear interfaces.
- Use test-first development for pure logic modules.
- Commit after each coherent milestone or subtask.
- Do not create root-level `PLAN.md`; this file is the canonical plan.
- Use Superpowers specs for focused feature slices when a milestone has product or workflow ambiguity.

## 3. Milestone Overview

| Milestone | Outcome | Needs Focused Spec? |
| --- | --- | --- |
| M0: SFTP Spike | Validate libssh2/libssh feasibility before UI investment | No, use `docs/technical-selection.md` |
| M1: macOS Project Foundation | Buildable app/test skeleton | No |
| M2: Domain Models and Persistence | Host, host key, transfer models persist safely | No |
| M3: Host Management | Create, edit, favorite, delete saved hosts | Yes, combined with M4 |
| M4: SSH Config Host Generation | Select alias, run `ssh -G`, create normal host | Yes, combined with M3 |
| M5: Credential and Host Key Security | Keychain secrets and app-managed host-key trust | Yes |
| M6: Local and Remote Browsing | Three-pane app with local and remote file panels | Yes |
| M7: Multi-File Transfer Queue | Bounded concurrent upload/download queue | Yes |
| M8: Productization for Internal Testing | Polish, diagnostics, packaging, notarization path | No |

## 4. Milestone Details

### M0: SFTP Spike

**Purpose:** Retire the biggest technical risk before building UI around an unproven transfer engine.

**Scope:**

- Create a minimal spike target or temporary command-line harness.
- Try libssh2 first.
- Connect to a controlled SSH/SFTP server.
- Verify host-key fingerprint extraction.
- Authenticate with password.
- Authenticate with SSH key and optional passphrase.
- List a remote directory.
- Upload multiple small files.
- Download multiple small files.
- Run two transfers to the same host concurrently without sharing unsafe session handles.
- Cancel or interrupt a transfer cleanly.

**Acceptance:**

- We know whether libssh2 can satisfy MVP.
- If libssh2 fails, the same checklist is run with libssh.
- The chosen library can be wrapped behind `RemoteFileSystem`.
- Packaging and signing implications are documented in `docs/technical-selection.md`.

**Follow-up:**

- Update `docs/technical-selection.md` with the final SFTP library decision.

### M1: macOS Project Foundation

**Purpose:** Create a buildable, testable native macOS project.

**Scope:**

- Create Xcode macOS app project named `wetrans`.
- Set bundle identifier and app display name.
- Add unit test and UI test targets.
- Establish source layout:

```text
wetrans/
  App/
  UI/
  AppKitAdapters/
  Domain/
  Persistence/
  SSHConfig/
  RemoteFileSystem/
  TransferQueue/
  Security/
wetransTests/
wetransUITests/
docs/
```

**Acceptance:**

- App builds.
- Unit test target runs.
- A minimal empty window launches.
- Xcode project settings are documented if non-obvious.

### M2: Domain Models and Persistence

**Purpose:** Implement the stable data foundation before UI workflows.

**Scope:**

- Implement models from `docs/data-model.md`:
  - `SavedHost`
  - `HostSource`
  - `AuthType`
  - `TrustedHostKey`
  - `TransferTask`
  - `TransferDirection`
  - `TransferStatus`
  - `FileItem`
  - `HostDraft`
- Implement JSON document storage:
  - `hosts.json`
  - `known_hosts.json`
  - `transfer_history.json`
- Implement schema version handling.
- Implement atomic writes.
- Implement validation rules.

**Acceptance:**

- Models encode/decode in unit tests.
- Invalid hosts fail validation.
- Atomic write path is tested with a temporary directory.
- Running transfer records are converted to interrupted/failed on startup.

### M3: Host Management

**Purpose:** Let users create and manage saved hosts without remote connectivity yet.

**Scope:**

- Build `HostCatalog`.
- Build host sidebar state.
- Add manual host form.
- Support create, edit, delete, favorite.
- Track recent connection metadata through explicit `markConnected` calls.
- Preserve last local and remote path fields.

**Acceptance:**

- User can create a manual host.
- Host appears in My Hosts.
- User can favorite/unfavorite host.
- Host persists after app restart.
- Deleting a host removes host metadata and triggers credential cleanup.

**Focused spec:** Use `docs/superpowers/specs/host-onboarding-and-management-spec.md`, shared with M4.

### M4: SSH Config Host Generation

**Purpose:** Implement "select from SSH Config" as a host creation workflow.

**Scope:**

- Implement `SSHConfigScanner`.
- Support basic `Include`.
- Extract multiple aliases from one `Host` line.
- Filter wildcard and negated aliases.
- Implement `SSHConfigResolver` using `/usr/bin/ssh -G <alias>`.
- Convert resolved config into `HostDraft`.
- Show unsupported-option warnings.
- Save generated hosts as normal `SavedHost` records.

**Acceptance:**

- `Host *`, `Host prod-*`, `Host ?`, and negated aliases are not selectable.
- Plain aliases are selectable.
- `ssh -G` output becomes editable host draft fields.
- Saved generated host does not require SSH Config at runtime.
- `originSSHConfigAlias` and `resolvedAt` are persisted as metadata.

**Focused spec:** Use `docs/superpowers/specs/host-onboarding-and-management-spec.md`, shared with M3.

### M5: Credential and Host Key Security

**Purpose:** Make connection security correct before real SFTP browsing.

**Scope:**

- Implement `CredentialStore` with Keychain Services.
- Store password and private key passphrase by host ID.
- Ensure secrets never appear in JSON.
- Implement `TrustedHostStore`.
- Persist trusted host keys in `known_hosts.json`.
- Add unknown-host prompt flow.
- Add changed-host-key blocking flow.

**Acceptance:**

- Password and passphrase are retrievable through Keychain.
- `hosts.json` contains no secret fields.
- Unknown host key requires explicit trust.
- Matching trusted host key connects.
- Changed host key blocks connection by default.

**Focused spec:** Create `docs/superpowers/specs/credential-and-host-key-spec.md` before implementation.

### M6: Local and Remote Browsing

**Purpose:** Deliver the core three-pane browsing experience.

**Scope:**

- Build SwiftUI app shell.
- Build host sidebar.
- Build AppKit-backed local file panel.
- Build AppKit-backed remote file panel.
- Implement `HostSessionManager`.
- Implement `RemoteFileSystem.listDirectory`.
- Preserve current local/remote path per host.
- Lazy-load remote directories.
- Show loading, empty, and error states.

**Acceptance:**

- User can browse local directories.
- User can connect to a host and browse remote directories.
- Remote browsing loads only the current path.
- Switching hosts preserves local and remote paths.
- Reconnect restores last remote path when possible.
- UI does not freeze during remote loading.

**Focused spec:** Create `docs/superpowers/specs/file-browsing-spec.md` before implementation.

### M7: Multi-File Transfer Queue

**Purpose:** Implement global bounded concurrent upload/download.

**Scope:**

- Build `TransferQueue`.
- Create one `TransferTask` per selected file.
- Default global running tasks: 3.
- Default running tasks per host: 2.
- Avoid unsafe sharing of SSH/SFTP session handles.
- Implement progress updates.
- Implement cancellation.
- Persist completed, failed, and cancelled task summaries.
- Mark running tasks interrupted on app startup.
- Refresh affected local or remote directory after completion.

**Acceptance:**

- User can upload multiple selected local files.
- User can download multiple selected remote files.
- Queue shows file, host, direction, progress, speed, status, and action.
- At most 3 tasks run globally by default.
- At most 2 tasks run per host by default.
- Cancelling a pending or running task updates state correctly.
- Switching hosts does not interrupt transfers.

**Focused spec:** Create `docs/superpowers/specs/transfer-queue-spec.md` before implementation.

### M8: Productization for Internal Testing

**Purpose:** Make the MVP usable by technical testers.

**Scope:**

- Add context menus for common actions.
- Add drag-and-drop if core transfer queue is stable.
- Improve error copy and debug detail views.
- Add lightweight app logs.
- Add settings for default local directory if needed.
- Prepare Developer ID signing and notarization path.
- Create internal test checklist.

**Acceptance:**

- App can be packaged for internal testers.
- Error states are understandable.
- Logs help diagnose failed connection and transfer issues.
- Internal testers can complete first connection and multi-file transfer without Terminal.

## 5. Focused Superpowers Specs To Create

Create focused specs only when starting the related milestone:

```text
docs/superpowers/specs/host-onboarding-and-management-spec.md
docs/superpowers/specs/credential-and-host-key-spec.md
docs/superpowers/specs/file-browsing-spec.md
docs/superpowers/specs/transfer-queue-spec.md
```

Each focused spec should define:

- User flow.
- UI states.
- Data changes.
- Module interfaces used.
- Error handling.
- Acceptance criteria.

## 6. Dependency Order

```text
M0 SFTP Spike
  -> M1 Project Foundation
  -> M2 Domain Models and Persistence
  -> M3 Host Management
  -> M4 SSH Config Host Generation
  -> M5 Credential and Host Key Security
  -> M6 Local and Remote Browsing
  -> M7 Multi-File Transfer Queue
  -> M8 Productization
```

M3 and M4 can overlap after M2 because both produce saved hosts.

M5 must precede real remote browsing and transfer work.

M6 must precede M7 because transfer actions depend on selected local/remote files and active host sessions.

## 7. Verification Strategy

### Per Milestone

- Run unit tests for changed modules.
- Run app build after UI-affecting changes.
- Commit only after tests or build pass.

### Before Internal Testing

- Build the macOS app.
- Run unit tests.
- Run UI smoke tests.
- Test manual host creation.
- Test SSH Config host generation.
- Test password authentication.
- Test key authentication.
- Test unknown and changed host-key flows.
- Test local browsing.
- Test remote browsing.
- Test multi-file upload.
- Test multi-file download.
- Test cancellation.
- Test host switching during transfer.

## 8. Deferred Scope

These stay outside MVP unless explicitly re-prioritized:

- Folder upload/download.
- Pause/resume.
- Resumable transfers.
- Directory sync.
- Remote file editing.
- ProxyJump.
- SSH Agent.
- Complex ProxyCommand.
- Keyboard-interactive auth.
- Built-in terminal.
- Multi-tab browsing.
- Mac App Store sandboxing.

## 9. Current Review Questions

Before implementation starts, confirm:

- Whether M0 should create a temporary command-line harness or go straight into an Xcode test target.
- Whether internal testing should require both password and key-auth test servers.
- Whether drag-and-drop should remain M8 polish or move into M7 once transfer queue works.
