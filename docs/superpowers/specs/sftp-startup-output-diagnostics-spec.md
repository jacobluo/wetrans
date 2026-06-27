# SFTP Startup Output Diagnostics Spec

## Purpose

Some hosts print shell startup messages during non-interactive SSH sessions. When that output reaches the SFTP subsystem stream, standards-based SFTP clients interpret the first bytes as binary packet length and fail with confusing protocol errors.

wetrans should diagnose this failure clearly without replacing the default SFTP transport.

## Background

Observed host behavior:

```text
ssh <host> true
Migration Tools environment loaded
...
```

Observed SFTP behavior:

```text
Received message too long 1298753394
Ensure the remote shell produces no output for non-interactive sessions.
```

The integer `1298753394` is `0x4d696772`, whose first bytes decode as `Migr`. This shows that remote startup text was read where SFTP expected a packet length.

## Product Decision

Primary remote operations remain standards-based SFTP through libssh2.

wetrans must not silently switch normal browsing or transfer behavior to shell-command transport for MVP. Shell-based compatibility may be designed later as an explicit advanced mode with reduced guarantees.

## Scope

This spec covers:

- Detecting likely remote startup-output pollution during SSH/SFTP setup and directory listing.
- Producing a user-readable error message that explains the remote configuration issue.
- Including enough diagnostic detail for the user to fix the host.
- Preserving the current libssh2-backed `RemoteFileSystem` boundary.
- Adding tests for message mapping and diagnostic extraction.

## Out of Scope

- Replacing SFTP with shell-command listing.
- Implementing SCP fallback.
- Implementing a custom SFTP server command.
- Supporting ProxyJump, ProxyCommand, agent forwarding, or keyboard-interactive auth.
- Automatically editing remote shell startup files.

## User Experience

When wetrans detects this class of failure, show a message like:

```text
SFTP could not start because the remote shell printed text before the SFTP protocol began.

Detected output prefix: "Migr"

Move login/setup echo output behind an interactive-shell guard, then retry.
Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
```

The message should be concise in the file panel, with the more detailed remediation available in any expanded error detail surface if introduced later.

## Detection Strategy

### libssh2 Error Inputs

Candidate source errors:

- `Failed getting banner`
- `Timeout waiting for response from SFTP subsystem`
- `Unable to open SFTP session`
- SFTP packet-length style messages if exposed by libssh2 in future

Not every one of these proves startup-output pollution. The diagnostic should use stronger wording only when there is evidence of non-protocol output.

### Evidence Sources

Potential evidence:

- A packet length value that decodes to printable ASCII bytes.
- A raw output prefix if future lower-level channel handling exposes it.
- A successful TCP/SSH handshake followed by SFTP subsystem timeout on hosts where `ssh host true` prints stdout.

MVP implementation can start with robust message mapping and helper functions that decode packet-length-like integers into printable prefixes.

### Prefix Decoding

If an error contains a decimal packet length, decode the first four big-endian bytes:

```text
1298753394 -> 0x4d696772 -> "Migr"
```

Only show the decoded prefix if all bytes are printable ASCII.

## Implementation Plan

1. Add a small diagnostic helper, for example `SFTPStartupOutputDiagnostic`.
2. Implement parsing for packet-length style messages:
   - Extract decimal values from messages such as `Received message too long 1298753394`.
   - Convert to a four-byte big-endian prefix.
   - Return a structured diagnostic when the prefix is printable.
3. Route relevant `RemoteFileSystemError.connectionFailed` messages through the helper before showing them in `MainBrowserViewModel.message(forRemoteError:)`.
4. Keep non-matching failures unchanged.
5. Add unit tests for:
   - Decoding `1298753394` to `Migr`.
   - Producing the startup-output diagnostic message.
   - Leaving unrelated connection failures unchanged.

## Acceptance Criteria

- A host whose SFTP error includes a packet-length-like startup prefix shows a specific startup-output diagnostic instead of a generic connection failure.
- The message tells the user to remove stdout output from non-interactive shell startup.
- The message names common files to inspect.
- Existing host key, auth, permission, and not-directory errors remain unchanged.
- `scripts/verify` passes.

## Future Compatibility Mode

A future design may add an explicit compatibility mode. That mode must be separately specified and should answer:

- Whether browsing, upload, and download all use the same transport.
- How progress and cancellation work.
- How paths are quoted safely.
- How host key trust remains consistent.
- How errors differ from SFTP errors.
- Whether the mode is per-host and visibly labeled in the UI.
