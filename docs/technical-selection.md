# wetrans Technical Selection

Status: MVP technical baseline
Source PRD: `docs/prd.md`

## 1. Purpose

This document records technical choices for the first wetrans implementation.

It focuses on choices that affect project shape:

- macOS app stack.
- SFTP library.
- SSH Config handling.
- Persistence format.
- Credential and host-key storage.
- Distribution model.

## 2. Summary of Decisions

| Area | Decision | Status |
| --- | --- | --- |
| App stack | SwiftUI + AppKit | Recommended |
| Distribution | Developer ID outside Mac App Store for MVP | Recommended |
| SSH Config | Use `ssh -G` to generate saved hosts | Decided |
| SFTP engine | Spike libssh2 first, compare libssh | Recommended |
| Production transfer engine | Native library adapter, not shell `sftp` | Recommended |
| Host metadata | JSON under Application Support | Recommended |
| Secrets | macOS Keychain | Decided |
| Host keys | App-managed `known_hosts.json` | Recommended |
| Project plan file | `docs/implementation-plan.md` | Decided |

## 3. App Stack

### Selected Direction

Use SwiftUI + AppKit.

### Why

wetrans is a file-management app. The difficult UI work is not static layout; it is dense macOS behavior:

- Columned file lists.
- Selection.
- Drag and drop.
- Context menus.
- Keyboard navigation.
- Focus behavior.
- Finder-adjacent user expectations.

SwiftUI is the current shell and file-panel implementation for the MVP. AppKit remains the safer future choice for file tables and high-fidelity macOS interactions when the product needs Finder-grade keyboard, drag/drop, and column behavior.

### Alternatives

#### Electron

Pros:

- Fast UI iteration.
- Large package ecosystem.
- Cross-platform potential.

Cons:

- Worse native file-manager feel.
- Heavier runtime.
- Keychain, file permissions, signing, and drag/drop need native bridges.
- Less aligned with "Mac native" product positioning.

Decision: reject for MVP.

#### Tauri

Pros:

- Lighter than Electron.
- Can use native Rust libraries.
- Cross-platform potential.

Cons:

- Still requires bridging for macOS-native file-manager behavior.
- More moving parts for an MVP focused only on Mac.
- Adds Rust/frontend split before product risk is retired.

Decision: reject for MVP.

## 4. SFTP Library

### Requirements

MVP needs:

- SSH handshake.
- Host-key inspection.
- Password authentication.
- Public-key authentication with optional passphrase.
- SFTP list directory.
- SFTP upload.
- SFTP download.
- Multi-file transfer by creating one task per selected file.
- Bounded transfer concurrency: default 3 global running tasks and 2 running tasks per host.
- Progress reporting.
- Cancellation.
- Reasonable macOS packaging.

### Option A: libssh2

Pros:

- Client-side SSH2 C library.
- Supports password and public-key authentication.
- Supports SFTP.
- Supports blocking and non-blocking modes.
- Smaller conceptual surface than libssh.
- Good fit for "SFTP client" MVP.

Cons:

- Lower-level API; upload/download loops and progress must be implemented by wetrans.
- Advanced OpenSSH features may require extra work.
- Swift packaging and binary distribution still need a spike.

Recommendation: spike first.

### Spike Step: Dynamic libssh2 Probe

The first implementation step uses a dynamic libssh2 probe instead of hard-linking the app to a Homebrew path. This keeps normal SwiftPM tests portable while allowing development machines to opt into a real probe through `WETRANS_LIBSSH2_DYLIB` or common Homebrew candidate paths.

This spike does not yet prove real SSH authentication or SFTP directory listing; those remain the next adapter slice.

### Adapter Slice: Real Connect and Directory Listing

The next adapter slice adds a real libssh2-backed client behind `RemoteFileSystem` for TCP connect, SSH handshake, host-key fingerprint extraction, password/key authentication, SFTP initialization, and single-directory listing. Unit tests still use fake clients; SFTP verification now runs by default through a local Docker OpenSSH fixture and `RemoteFileSystemRealHostIntegrationTests`, with `WETRANS_SFTP_INTEGRATION_FILE` available for explicit external-host overrides.

Upload, download, cancellation, and queue behavior remain future transfer-queue work.

### Option B: libssh

Pros:

- Broader SSH feature surface.
- Provides client APIs, SFTP subsystem, and more SSH protocol support.
- May be better long-term if ProxyJump, agent forwarding, or more SSH features become central.

Cons:

- Larger surface area.
- More capability than MVP needs.
- Still C integration and packaging work.

Recommendation: keep as fallback if libssh2 blocks on key formats, host-key verification, packaging, or cancellation behavior.

### Option C: OpenSSH command-line tools

Pros:

- Leverages system SSH behavior.
- Closest to user terminal config behavior.
- Useful for early experiments.

Cons:

- Harder to provide precise progress, cancellation, structured errors, and queue control.
- Shelling out for transfers weakens the app architecture.
- Complex to manage password prompts and interactive auth in a GUI.

Recommendation: allowed for spike validation only; reject as production transfer engine.

### Decision: Remote Startup Output and SFTP Compatibility

Some SSH servers print login banners or environment setup text from shell startup files such as `.bashrc`, `.profile`, `/etc/profile`, or `/etc/bashrc`. If that output is written to the SFTP subsystem stream before binary SFTP packets, standards-based SFTP clients cannot safely treat the stream as valid SFTP. Common clients such as OpenSSH `sftp`, WinSCP, Cyberduck, Transmit, ForkLift, and FileZilla generally fail with packet length or protocol errors rather than silently filtering arbitrary bytes.

Decision:

- Keep the primary remote file implementation as standards-based SFTP through libssh2.
- Do not replace the production transfer engine with shell-command browsing or transfer as the default behavior.
- Treat remote non-interactive startup output as a server-side compatibility problem, not as normal SFTP traffic.
- Add or preserve user-facing diagnostics that identify this case clearly, for example by decoding packet-length-like prefixes such as `Migr` and explaining that the remote shell is printing text before SFTP starts.
- Recommend that users move banner/setup `echo` output behind an interactive-shell guard so `ssh host true` and SFTP subsystem sessions produce no stdout text.
- Consider an explicit advanced compatibility mode only as a future design, not as MVP default behavior. Any such mode must be documented as a fallback with reduced guarantees for progress, transfer semantics, cancellation, and protocol fidelity.

Rationale:

- SFTP is a binary protocol; arbitrary prelude text cannot be filtered with full confidence without risking mis-parsing valid protocol bytes.
- Matching mature client behavior keeps wetrans predictable and easier to debug.
- Clear diagnostics help users fix the remote environment while preserving the integrity of the main SFTP implementation.
- Shell-command fallback may be useful for constrained environments, but it is a separate transport choice and should not blur the `RemoteFileSystem` contract without a dedicated design review.

## 5. SSH Config Handling

Decision:

- Use SSH Config only during host generation.
- Run `/usr/bin/ssh -G <alias>` to resolve the final effective config.
- Save a normal `SavedHost`.
- Preserve `originSSHConfigAlias` and `resolvedAt` as metadata.
- Do not silently sync saved hosts from future SSH Config changes.

Rationale:

- Keeps runtime connection model unified.
- Avoids surprising changes when users edit `~/.ssh/config`.
- Makes transfer queue and host session state depend on stable `hostId`.

## 6. Persistence Format

### Selected Direction

Use local JSON documents under:

```text
~/Library/Application Support/wetrans/
```

Files:

- `hosts.json`
- `known_hosts.json`
- `transfer_history.json`

### Why JSON

Pros:

- Simple to inspect during early development.
- Good enough for small host and transfer metadata.
- Easy to version and migrate.
- No database dependency.

Cons:

- Needs atomic writes.
- Needs migration discipline.
- Not ideal for very large transfer histories.

Decision: use JSON for MVP. Revisit SQLite only if transfer history or search grows.

## 7. Credential Storage

Decision:

- Store passwords in Keychain.
- Store private key passphrases in Keychain.
- Do not store secrets in JSON.

Suggested Keychain services:

```text
wetrans.ssh.password
wetrans.ssh.keyPassphrase
```

Use `hostId` as the account key.

## 8. Host-Key Storage

Decision:

- Store app-managed trusted host keys in `known_hosts.json`.
- Do not mutate the user's OpenSSH `known_hosts` file in MVP.

Rationale:

- Avoids surprising changes to user SSH environment.
- Keeps trust decisions scoped to wetrans.
- Simplifies testing and migration.

Future option:

- Offer read-only comparison with OpenSSH `known_hosts`.
- Offer import/use system known hosts only after explicit design.

## 9. Swift Package and Xcode Layout

Selected first implementation:

- SwiftPM-first macOS app skeleton.
- Xcode can open `Package.swift` directly during early implementation.
- Commit a generated `.xcodeproj` later only when app bundle settings, UI tests, signing, or notarization workflows need stable project metadata.
- Keep C library adapter isolated in `RemoteFileSystem`.

Avoid premature over-modularization. The first useful split is:

- Executable app target.
- Core library target.
- Unit test target.
- Later Xcode app/UI-test targets when bundle-level workflows become necessary.

## 10. Distribution and Signing

MVP:

- `scripts/package` builds `dist/wetrans.app` and `dist/wetrans.zip`.
- If `WETRANS_DEVELOPER_ID_APPLICATION` is set, the script signs with Developer ID using hardened runtime options.
- If both `WETRANS_DEVELOPER_ID_APPLICATION` and `WETRANS_NOTARYTOOL_PROFILE` are set, the script submits the zip through `xcrun notarytool --wait` and staples the app after success.
- On development machines without signing credentials, the script leaves signing and notarization skipped while still producing local artifacts for smoke testing.

Later:

- Revisit Mac App Store only after evaluating sandbox impact.

## 11. Spike Plan

Before building the full browser UI, run a technical spike:

1. Create a minimal macOS command-line or test harness target.
2. Link libssh2.
3. Connect to a test SSH server.
4. Verify host-key fingerprint extraction.
5. Authenticate with password.
6. Authenticate with key + passphrase.
7. List a remote directory.
8. Upload multiple small files.
9. Download multiple small files.
10. Run two transfers to the same host concurrently without sharing unsafe session handles.
11. Cancel or interrupt a transfer cleanly.

Spike success means:

- libssh2 can satisfy MVP SFTP needs.
- Packaging path is understood.
- The `RemoteFileSystem` interface is validated.

Spike failure means:

- Repeat the same checklist with libssh.

## 12. References

- libssh2 official site and API documentation: https://libssh2.org/
- libssh official API documentation: https://api.libssh.org/stable/
- Apple Keychain Services documentation: https://developer.apple.com/documentation/security/keychain-services
- Apple SwiftUI AppKit integration documentation: https://developer.apple.com/documentation/swiftui/appkit-integration
