# Logs, Debug Detail, and Checklist Lite Spec

## 1. Purpose

wetrans is ready for more internal testing, but failures are still hard to report. This slice adds a minimal diagnostic surface before broader UI E2E and directory-transfer work:

- lightweight app logs at important browser and transfer boundaries
- copyable, redacted debug detail for the latest file-panel failure
- an internal tester checklist that does not require Terminal for normal product flows

## 2. Product Boundary

This is a lite diagnostics slice. It does not add a full log viewer, log export bundle, preferences UI, crash reporting, telemetry upload, or a persistent debug database.

## 3. In Scope

- Add a small diagnostic formatter for user-copyable failure details.
- Redact obvious local usernames, home paths, passwords, passphrases, private-key passphrase labels, and long private path prefixes from copied diagnostics.
- Add a copy diagnostic action for failed local and remote file panels.
- Add an OSLog-backed app logger with injectable test sink.
- Log high-value lifecycle events:
  - local directory refresh failed
  - remote directory refresh failed
  - transfer tasks enqueued
  - transfer completion event observed
- Add an internal tester checklist document.

## 4. Out of Scope

- Capturing raw libssh2 packets or SSH credentials.
- Logging host passwords, passphrases, authorization headers, or private key contents.
- A user-visible logs window.
- A packaged support bundle.
- Sending logs to any external service.

## 5. UI Behavior

When a file panel enters a failed state, the failed-state view shows a compact `Copy Debug Detail` button. Pressing it writes a plain-text diagnostic report to the injected pasteboard writer.

The visible error copy remains readable and concise. The debug detail may include more context, but it must be redacted.

## 6. Debug Detail Format

The copied text should be stable enough for bug reports:

```text
wetrans debug detail
panel: Remote
path: /srv/project
message: Permission denied: /srv/project
host: Example Host
```

If there is no selected host, the host line should be omitted.

## 7. Logging

Production logging uses Apple's unified logging through `os.Logger`. Tests use an in-memory logger sink.

Logs should capture event names and non-secret metadata only. Paths and user-visible messages must pass through the same redaction helper used for copyable diagnostics.

## 8. Testing

- Unit tests cover diagnostic detail formatting and redaction.
- View model tests cover copying local and remote panel debug detail.
- View model tests cover transfer enqueue logging and remote refresh failure logging through an injected logger.
- SwiftUI smoke tests cover the failed-state copy button rendering at compile level.

## 9. Acceptance Criteria

- Failed file panels expose a copyable debug detail action.
- Copied debug detail includes panel, path, message, and selected host when present.
- Copied debug detail redacts sensitive-looking content.
- Browser and transfer events can be logged through an injectable logger.
- Internal tester checklist exists under `docs/`.
- `scripts/verify` passes.
