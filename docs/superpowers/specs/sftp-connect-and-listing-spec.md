# SFTP Connect and Listing Spec

## 1. Purpose

This spec turns the libssh2 adapter skeleton into a real remote browsing foundation.

The feature must let `LibSSH2RemoteFileSystem`:

- Open a TCP connection to a saved host.
- Create a libssh2 SSH session.
- Verify the remote host key through the existing trusted-host model.
- Authenticate with password or SSH key plus optional passphrase.
- Open an SFTP session.
- List one remote directory path.

It intentionally does not implement upload, download, transfer queue integration, ProxyJump, SSH Agent, or UI.

## 2. Design Direction

Use a small, testable client boundary between `LibSSH2RemoteFileSystem` and raw libssh2 calls:

```text
LibSSH2RemoteFileSystem
  -> LibSSH2ClientFactory
  -> LibSSH2Client
  -> Darwin TCP socket + dynamically-loaded libssh2 symbols
```

Adapter unit tests should use fake clients and never require a real SSH server or libssh2 dylib. A real integration test may exist, but it must be opt-in through environment variables and skipped by default.

## 3. Module Boundaries

### 3.1 LibSSH2RemoteFileSystem

Responsibilities:

- Initialize the libssh2 runtime.
- Create one client per remote session.
- Ask the client to connect and authenticate.
- Read the client-provided host key and run `HostKeyVerificationPolicy`.
- Preserve active clients by `RemoteSession.id`.
- Delegate directory listing to the active client.
- Disconnect and remove the active client.

It must not directly call `dlopen`, `socket`, or raw libssh2 functions.

### 3.2 LibSSH2Client

Responsibilities:

- Establish TCP and SSH session state.
- Report the remote host key as `LibSSH2HostKey`.
- Authenticate using `ConnectionAuth`.
- Open SFTP.
- List exactly one requested directory.
- Close SFTP/session/socket resources on disconnect.

### 3.3 LibSSH2 Dynamic Implementation

Responsibilities:

- Dynamically resolve the libssh2 symbols needed for this slice.
- Use blocking mode for MVP simplicity.
- Convert libssh2 return codes to `LibSSH2Error`.
- Convert SFTP directory entries into `FileItem`.
- Avoid exporting raw libssh2 pointer types from public adapter APIs.

## 4. Host-Key Behavior

The adapter receives a `TrustedHostStore`.

Connection flow:

```text
connect(spec)
  -> runtime.initialize()
  -> client.connect(spec)
  -> candidate = client.hostKey()
  -> trusted = trustedHostStore.lookup(spec.hostId, spec.hostname, spec.port)
  -> decision = HostKeyVerificationPolicy.decide(trusted, candidate)
```

Decision behavior:

- `trusted`: record verification time and continue authentication.
- `requiresTrust`: throw `RemoteFileSystemError.hostKeyRequiresTrust(candidate)`.
- `blockedChangedKey`: throw `RemoteFileSystemError.hostKeyChanged(expected, actual)`.

This slice does not auto-trust unknown keys. The UI prompt can be implemented later by catching `hostKeyRequiresTrust`.

## 5. Authentication

Supported for this slice:

- `.password(String?)`
- `.sshKey(identityFile: String, passphrase: String?)`

Rules:

- Missing password is passed as an empty string to libssh2 for now. Interactive prompts are out of scope.
- SSH key authentication uses the same identity file as both public and private key input. A later polish slice can derive `.pub` paths.
- Unsupported interactive auth should surface as `RemoteFileSystemError.connectionFailed`.

## 6. Directory Listing

`listDirectory(path, in:)` must:

- Require an active connected session.
- Open only the requested path.
- Read entries until libssh2 reports end of directory.
- Skip `"."` and `".."`.
- Return `FileItem` values with:
  - `name`
  - joined absolute path
  - directory flag
  - symlink flag when attributes expose it
  - size when available
  - modified date when available
  - Unix-style permission text when available

No recursive scanning is allowed.

## 7. Error Mapping

Use existing `RemoteFileSystemError` where possible, and add cases only when the UI needs structured recovery:

- `.disconnected` for list calls without an active session.
- `.connectionFailed(String)` for socket, handshake, auth, SFTP init, and libssh2 failures.
- `.permissionDenied(String)` when directory open/list indicates permission denial.
- `.notDirectory(String)` when directory open/list indicates the path is not a directory.
- `.hostKeyRequiresTrust(TrustedHostKey)` for first-contact trust decisions.
- `.hostKeyChanged(expected: TrustedHostKey, actual: TrustedHostKey)` for changed keys.

The user-facing copy can be refined later; this slice should preserve structured errors.

## 8. Real Integration Test

Add a skipped-by-default integration test for real environments.

It should run only when all required variables are present:

```text
WETRANS_RUN_SFTP_INTEGRATION=1
WETRANS_SFTP_HOST
WETRANS_SFTP_PORT
WETRANS_SFTP_USER
WETRANS_SFTP_PASSWORD or WETRANS_SFTP_IDENTITY_FILE
WETRANS_SFTP_LIST_PATH
WETRANS_LIBSSH2_DYLIB
```

The test should connect, pre-trust the provided host key if a fingerprint variable is supplied, and list the requested path.

If no real environment is configured, normal `swift test` must pass with the integration test skipped.

## 9. Acceptance Criteria

- `LibSSH2RemoteFileSystem.connect` no longer throws the placeholder unsupported error.
- Unit tests prove runtime initialization, client creation, host-key decisions, auth call order, session storage, listing, and disconnect cleanup.
- Unknown host keys throw a structured trust-required error.
- Changed host keys throw a structured changed-key error.
- Trusted matching keys allow authentication and return a `RemoteSession`.
- `listDirectory` delegates to the connected client and returns `FileItem` values.
- `disconnect` closes and removes the session client.
- Normal tests do not require libssh2 or a real SSH server.
- `swift test` and `swift build` pass.

## 10. Out of Scope

- Upload.
- Download.
- Transfer queue.
- Drag and drop.
- Remote file mutation.
- ProxyJump.
- SSH Agent.
- Keyboard-interactive authentication.
- Non-blocking libssh2 event loops.
- Production packaging of libssh2.
