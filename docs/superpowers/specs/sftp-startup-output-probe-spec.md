# SFTP Startup Output Probe Spec

## Purpose

When standard SFTP startup fails, wetrans should be able to run a short SSH diagnostic probe that detects whether the remote host prints text during non-interactive SSH sessions.

The probe improves error clarity. It does not repair, bypass, or replace the standard libssh2 SFTP transport.

## Background

Some hosts load shell tooling from startup files and print messages even when the SSH session is non-interactive. A known example is a host where:

```text
ssh -T <host> true
Migration Tools environment loaded
...
```

On the same host, OpenSSH `sftp` fails with:

```text
Received message too long 1298753394
Ensure the remote shell produces no output for non-interactive sessions.
```

The existing startup-output diagnostic can decode packet-length evidence when the SFTP error contains a value such as `1298753394`. libssh2 may also surface only a generic startup failure such as `Unable to open SFTP session`. In those cases, wetrans needs a way to gather stronger evidence without making SFTP itself non-standard.

## Product Decision

wetrans will keep standard libssh2 SFTP as the primary remote file transport.

The startup output probe is a diagnostic tool:

- It may run after selected SFTP startup failures.
- It must not silently switch the host to a shell, SCP, or custom SFTP compatibility transport.
- It must not attempt to discard startup output from the SFTP byte stream.

## Scope

This spec covers:

- A short-lived libssh2-backed SSH exec probe.
- Automatic probe triggering after likely SFTP startup failures.
- A structured probe result for stdout, stderr, no output, and probe failure.
- User-facing error wording that distinguishes strong and weak evidence.
- Tests for trigger rules, result mapping, and output truncation.

This spec does not cover:

- Custom libssh2 protocol recovery.
- SCP fallback or shell-command file browsing.
- Automatically editing remote shell startup files.
- Agent forwarding, ProxyJump, ProxyCommand, keyboard-interactive authentication, or other SSH feature expansion.

## Architecture

Add a small diagnostic module behind the remote file system layer:

```swift
public protocol SSHStartupOutputProbing {
    func probe(_ spec: ConnectionSpec) async throws -> SSHStartupOutputProbeResult
}
```

The production adapter should be libssh2-backed, for example `LibSSH2StartupOutputProbe`. It should use the same connection facts as normal SFTP:

- hostname
- port
- username
- authentication method
- trusted host key policy already represented by the caller's connection flow

The probe should open a new short-lived SSH session instead of reusing the failed SFTP session. A failed SFTP init can leave the original session in an uncertain state, and diagnostic work should not mutate the main browsing session.

## Probe Flow

The production probe should:

1. Open a TCP connection.
2. Perform libssh2 SSH handshake.
3. Authenticate with the same `ConnectionSpec`.
4. Open an SSH session channel.
5. Execute the fixed command `true`.
6. Read stdout and stderr until command completion, timeout, or output cap.
7. Close the channel, session, and socket.
8. Return a structured result.

The command must be hard-coded. The probe must not concatenate user-provided paths or shell fragments.

## libssh2 Requirements

The existing dynamic symbol loader will need channel and exec symbols, likely including:

- `libssh2_channel_open_ex`
- `libssh2_channel_process_startup`
- `libssh2_channel_read_ex`
- `libssh2_channel_eof`
- `libssh2_channel_close`
- `libssh2_channel_free`

Exact symbol choices can be refined during implementation, but they must stay private to the libssh2 probe adapter. UI and view model callers should depend only on the probe protocol and structured result.

## Trigger Rules

Automatic probing should run only after likely SFTP startup failures:

- `RemoteFileSystemError.connectionFailed("Unable to open SFTP session")`
- `RemoteFileSystemError.connectionFailed("Timeout waiting for response from SFTP subsystem")`
- packet-length style failures already detected by `SFTPStartupOutputDiagnostic`

Automatic probing should not run for:

- DNS or TCP connection failure.
- SSH authentication failure.
- host key changed.
- host key requires trust.
- permission denied.
- not directory.
- stale session retry failures that already reconnect and fail on directory operations without startup evidence.

Probe failure must not replace the original SFTP error. It may be attached as secondary diagnostic detail when the UI has a detail surface.

## Result Model

The result should preserve evidence without exposing unnecessary data:

```swift
public struct SSHStartupOutputProbeResult: Equatable, Sendable {
    public let stdoutPreview: String
    public let stderrPreview: String
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool
}
```

Output previews should be capped at 4096 bytes per stream. Invalid UTF-8 should be replaced or rendered safely. Logs should avoid recording full probe output; user-facing UI may show a short preview because the diagnostic concerns the user's own host.

## Diagnostic Interpretation

Use three levels:

- **Strong evidence:** stdout is non-empty. Message: remote shell printed text during a non-interactive SSH session before SFTP could start.
- **Weak evidence:** stdout is empty but stderr is non-empty. Message: remote startup produced diagnostics; if SFTP still fails, inspect startup files.
- **No evidence:** both streams are empty. Keep the original SFTP error as primary and state that the startup-output probe did not find non-interactive output.

For strong evidence, the UI should suggest guarding setup output behind an interactive-shell check and name common files:

```text
~/.bashrc, ~/.profile, /etc/profile, /etc/bashrc
```

## UI Behavior

When automatic probing produces strong evidence, the remote panel error should show a concise startup-output diagnostic and include a short detected output preview.

When probing produces weak evidence, the remote panel should keep the SFTP failure context and mention that remote startup diagnostics were printed.

When probing finds no output or fails, the UI should not overstate the startup-output hypothesis.

## Security And Privacy

- The probe command is fixed to `true`.
- The probe has a 5 second timeout.
- Output capture is capped at 4096 bytes per stream.
- Full probe output is not persisted.
- Logs may include only a short sanitized prefix and truncation flags.
- Probe output must not be added to committed fixtures, screenshots, or documentation for real private hosts.
- Authentication and host key handling must remain consistent with the normal connection path.

## Testing

Unit tests should cover:

- Trigger rules for startup-like failures and non-startup failures.
- Strong, weak, and no-evidence message mapping.
- Output truncation and invalid UTF-8 handling.
- Probe failure preserving the original SFTP error.

libssh2 adapter tests should use a fake symbol/client layer where practical. The real host integration suite should not depend on a private host with startup output. A local fixture can be added later if the Docker OpenSSH setup can safely reproduce non-interactive startup stdout without secrets.

## Acceptance Criteria

- A generic SFTP startup failure can surface a startup-output diagnostic when the probe detects stdout from `true`.
- The original SFTP error is preserved when the probe fails or finds no output.
- The app does not switch to shell, SCP, or custom SFTP compatibility transport.
- The probe uses a fixed command, a timeout, and capped output.
- Existing packet-length diagnostics continue to work.
- Focused tests cover trigger and message behavior.
- `scripts/verify` passes before implementation is completed.
