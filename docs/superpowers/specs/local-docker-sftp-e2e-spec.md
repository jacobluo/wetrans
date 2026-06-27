# Local Docker SFTP E2E Spec

Status: Implemented

Implemented on 2026-06-27. Full `scripts/verify` reaches the native UI smoke step but is currently blocked by macOS Accessibility permission in this environment.

## 1. Purpose

Replace the default external real-host SFTP verification path with a local Docker-backed OpenSSH server.

The default E2E path should remain a real libssh2/SFTP integration test, but it should not depend on a public VM, personal SSH keys, fixed network access, or machine-specific host metadata. A developer or CI runner with Docker available should be able to run the default SFTP E2E path from a clean checkout.

This spec supersedes the default-host parts of `real-host-sftp-smoke-spec.md` and `e2e-default-path-spec.md`. External real hosts may remain as an explicit override, but they are no longer part of the default verification contract.

## 2. Product Boundary

The default SFTP E2E target is a local Docker container running a general OpenSSH server:

```text
lscr.io/linuxserver/openssh-server:latest
```

The test still exercises the same app-facing path:

```text
LibSSH2RemoteFileSystem
  -> libssh2 runtime/client
  -> SSH authentication
  -> SFTP connect/list/upload/download
```

The Docker fixture is infrastructure for tests only. It is not an app runtime dependency and must not be referenced by production code.

## 3. Default E2E Behavior

`scripts/e2e` should become:

```text
scripts/e2e
  -> start local Docker OpenSSH fixture
  -> generate temporary SFTP integration config
  -> run SFTP integration tests against 127.0.0.1:<dynamic-port>
  -> clean up container and temporary files
  -> app build/run smoke
  -> optional full UI E2E when WETRANS_E2E_RUN_FULL=1
```

The fixture startup must bind only to loopback:

```text
127.0.0.1:<dynamic-host-port> -> container port 2222
```

The script should use a dynamic host port to avoid collisions across local runs and CI jobs.

## 4. Authentication Coverage

The local OpenSSH fixture should cover both authentication modes supported by the app's connection model:

1. SSH key authentication.
2. Password authentication.

A single container may be used for both modes as long as it enables both:

```text
USER_NAME=wetrans
PUBLIC_KEY_FILE=<temporary public key path>
PASSWORD_ACCESS=true
USER_PASSWORD=<temporary generated password>
SUDO_ACCESS=false
```

The generated SFTP config should contain two logical hosts that point to the same container endpoint:

```json
{
  "hosts": [
    {
      "name": "local-openssh-key",
      "hostname": "127.0.0.1",
      "port": 32768,
      "username": "wetrans",
      "identityFile": "/tmp/wetrans-sftp-fixture/id_ed25519",
      "listPath": "."
    },
    {
      "name": "local-openssh-password",
      "hostname": "127.0.0.1",
      "port": 32768,
      "username": "wetrans",
      "passwordEnv": "WETRANS_SFTP_FIXTURE_PASSWORD",
      "listPath": "."
    }
  ]
}
```

`passwordEnv` is a new test-fixture field. It names an environment variable containing the password; the password value itself must not be written to committed files or logs.

## 5. Test Suite Changes

The current upload/download test logic can be preserved.

Expected changes:

- Keep the existing connect/list/upload/download assertions.
- Extend the test config model so a host can specify either:
  - `identityFile` with optional `passphraseEnv`, or
  - `passwordEnv`.
- Build `ConnectionSpec.auth` from the selected auth field.
- Keep the existing `RemoteFileSystemRealHostIntegrationTests` class name for this implementation to avoid breaking current scripts; a later cleanup may rename it to `RemoteFileSystemSFTPIntegrationTests`.
- Replace `testCommittedFixtureDecodesOpenclawVM` with coverage for the local Docker fixture/config shape.

The test should continue to cover for each configured host:

- connect and list `listPath`
- upload one file
- upload multiple files
- upload a directory with nested children
- download one file
- download multiple files
- download a directory with nested children
- byte-for-byte content checks for downloaded files

## 6. Fixture Script

Add a script with one clear responsibility, for example:

```text
scripts/local-sftp-fixture
```

The script should:

- require Docker CLI and a reachable Docker daemon
- generate a temporary `ed25519` key pair
- generate a temporary random password
- start `lscr.io/linuxserver/openssh-server:latest`
- wait until `127.0.0.1:<port>` accepts TCP connections
- write a temporary JSON config file compatible with the XCTest fixture model
- run a provided command with `WETRANS_SFTP_INTEGRATION_FILE` and `WETRANS_SFTP_FIXTURE_PASSWORD` exported
- clean up the container and temporary directory on success, failure, or interruption

Preferred calling shape:

```bash
scripts/local-sftp-fixture -- swift test --filter wetransTests.RemoteFileSystemRealHostIntegrationTests
```

This keeps Docker setup outside XCTest and avoids adding Docker dependencies to Swift test code.

## 7. External Host Override

External hosts are no longer part of the default path.

Keep `WETRANS_SFTP_INTEGRATION_FILE` as an explicit developer override for manual validation against real external hosts:

```bash
WETRANS_SFTP_INTEGRATION_FILE=/path/to/external-sftp-config.json \
swift test --filter wetransTests.RemoteFileSystemRealHostIntegrationTests
```

Rules for external override configs:

- no secrets in config files
- key auth uses local `identityFile` paths only
- password auth uses `passwordEnv` only
- passphrases use `passphraseEnv` only
- host key fields remain optional and are trusted only in temporary test stores when absent

No committed fixture should point to `openclaw-vm` or any other external host as the default.

## 8. Remote Data and Cleanup

The existing transfer E2E writes should remain under a unique remote root:

```text
/tmp/wetrans-e2e-<uuid>/
```

The implementation should avoid deleting arbitrary remote paths. If remote cleanup is added, it must only delete paths that begin with the generated `wetrans-e2e-` root for the current test run.

Container cleanup is mandatory. The fixture script must remove the container even when tests fail.

## 9. Documentation Updates

Update long-lived docs and workflow text so they no longer present external real-host access as required by default:

- `README.md`
- `docs/README.md`
- `docs/real-host-sftp-smoke.md`, kept as a short compatibility note until references can be renamed to `docs/sftp-e2e.md`
- `docs/architecture-design.md`
- `docs/implementation-plan.md`
- `.codebuddy/rules/testing.mdc`
- `.codebuddy/rules/workflow.mdc` if it references real-host default E2E
- `scripts/setup`

The docs should state:

- default SFTP E2E uses local Docker OpenSSH
- Docker is required for default SFTP E2E
- external host configs are opt-in only
- no private keys, passwords, passphrases, tokens, or `.env` files are committed

## 10. Failure Behavior

If Docker is missing or the daemon is unavailable, `scripts/e2e` should fail with a clear message:

```text
Docker is required for local SFTP E2E. Install/start Docker, then rerun scripts/e2e.
```

If the container fails to become reachable, the script should print the container logs, then clean up.

Failure output may include:

- container name
- localhost port
- config file path under the temporary directory
- host names such as `local-openssh-key`

Failure output must not include:

- generated private key contents
- generated password value
- authorization headers or other credentials

## 11. Acceptance Criteria

- `scripts/e2e` no longer requires `openclaw-vm`, public network access, or `~/.ssh/openclaw_vm`.
- `scripts/e2e` starts a local Docker OpenSSH fixture before SFTP integration tests.
- The Docker fixture binds only to `127.0.0.1` on a dynamic host port.
- The default SFTP integration suite covers SSH key authentication.
- The default SFTP integration suite covers password authentication.
- For both auth modes, tests cover connect/list/upload/download for single files, multiple files, and nested directories.
- `WETRANS_SFTP_INTEGRATION_FILE` remains available for explicit external-host override.
- No committed default fixture points to an external host.
- Documentation no longer describes real external host access as required by default.
- Docker/container/temp-file cleanup runs on success, failure, and interruption.
- `scripts/verify` uses the updated `scripts/e2e` path.

## 12. Technical Validation Notes

A manual spike on 2026-06-27 verified that the existing SFTP integration tests can run against a local Docker SFTP endpoint using a temporary key and generated `WETRANS_SFTP_INTEGRATION_FILE`.

The validated spike used `atmoz/sftp:alpine` and passed the existing three-test `RemoteFileSystemRealHostIntegrationTests` suite. This proves the current test logic is portable to Docker. The implementation should use `lscr.io/linuxserver/openssh-server:latest` instead, because it is a general OpenSSH server, supports arm64, and can cover both password and key authentication.
