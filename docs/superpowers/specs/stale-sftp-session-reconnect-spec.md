# Stale SFTP Session Reconnect Spec

## Purpose

When a Mac sleeps, the network drops, or a remote server closes an idle SSH/SFTP connection, wetrans can keep a cached `RemoteSession` that is no longer usable. The next remote refresh may fail with a low-level libssh2 message such as:

```text
Unable to send FXP_OPEN*
```

wetrans should recover from this stale-session class by dropping the cached session and retrying the directory listing on a fresh connection.

## Scope

- Detect a failed remote directory listing on an existing cached session.
- Disconnect and remove the cached session for that host.
- Retry the same directory listing once with a fresh connection.
- Preserve the current remote path and local path.
- Keep the existing `RemoteFileSystem` protocol and libssh2 transport.
- Add tests for stale-session reconnect behavior.

## Out of Scope

- Background keepalive or heartbeat.
- Infinite retry loops.
- Retrying authentication, host key trust, permission denied, or not-directory errors.
- Shell/SCP compatibility transport.
- Changing remote host files or settings.

## User Experience

After long idle time or temporary network loss, pressing refresh should reconnect automatically once. If the new connection succeeds, the remote panel should load normally. If reconnect or listing still fails, the user should see the current error message.

## Detection Strategy

For MVP, retry only when a listing on a cached session throws `RemoteFileSystemError.connectionFailed`. These failures include stale transport errors such as `Unable to send FXP_OPEN*`.

Do not retry semantic remote errors:

- `hostKeyRequiresTrust`
- `hostKeyChanged`
- `notDirectory`
- `permissionDenied`
- `disconnected`

## Acceptance Criteria

- A cached session whose first directory listing fails with `connectionFailed` is disconnected and replaced.
- The same remote path is retried once on a fresh session.
- A successful retry returns the directory items and leaves the host marked connected.
- Non-retryable remote errors still surface without reconnecting.
- `scripts/verify` passes.
