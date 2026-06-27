# Local Docker SFTP E2E Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Replace the default external real-host SFTP E2E path with a local Docker OpenSSH fixture that covers key and password authentication.

**Architecture:** Keep Docker orchestration in shell scripts and keep Swift tests focused on SFTP behavior. `scripts/local-sftp-fixture` starts `lscr.io/linuxserver/openssh-server:latest`, writes a temporary config, exports `WETRANS_SFTP_INTEGRATION_FILE` and `WETRANS_SFTP_FIXTURE_PASSWORD`, then runs the requested command. The XCTest suite reads that config, supports either `identityFile` or `passwordEnv`, and skips live SFTP tests when no config is provided outside `scripts/e2e`.

**Tech Stack:** Bash, Docker CLI, SwiftPM, XCTest, libssh2-backed SFTP.

---

### Task 1: Test fixture config model

**Files:**
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Delete: `wetransTests/Fixtures/real-host-smoke.example.json`
- Create: `wetransTests/Fixtures/local-sftp-smoke.example.json`

- [x] **Step 1: Write failing config decoding test**

Replace `testCommittedFixtureDecodesOpenclawVM` with a test that loads `local-sftp-smoke.example.json` and asserts two hosts:

```swift
XCTAssertEqual(config.hosts.map(\.name), ["local-openssh-key", "local-openssh-password"])
XCTAssertEqual(config.hosts[0].auth(environment: [:]), .sshKey(identityFile: "/tmp/wetrans-sftp-fixture/id_ed25519", passphrase: nil))
XCTAssertEqual(config.hosts[1].auth(environment: ["WETRANS_SFTP_FIXTURE_PASSWORD": "secret"]), .password("secret"))
```

- [x] **Step 2: Run red test**

Run: `swift test --filter RemoteFileSystemRealHostIntegrationTests/testCommittedFixtureDecodesLocalOpenSSHConfig`

Expected: FAIL because `passwordEnv`, `auth(environment:)`, and the new fixture do not exist yet.

- [x] **Step 3: Add fixture model support**

Make `identityFile` optional, add `passwordEnv`, and add `auth(environment:) -> ConnectionAuth` that returns `.sshKey` for key hosts and `.password` for password hosts.

- [x] **Step 4: Add local fixture file**

Create `wetransTests/Fixtures/local-sftp-smoke.example.json` with non-secret localhost example hosts for key and password auth.

- [x] **Step 5: Run green test**

Run: `swift test --filter RemoteFileSystemRealHostIntegrationTests/testCommittedFixtureDecodesLocalOpenSSHConfig`

Expected: PASS.

### Task 2: Gate live SFTP tests behind explicit config

**Files:**
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`

- [x] **Step 1: Write failing skip behavior test**

Add a test for `configURL(environment: [:])` that expects an `XCTSkip` when no `WETRANS_SFTP_INTEGRATION_FILE` is present.

- [x] **Step 2: Run red test**

Run: `swift test --filter RemoteFileSystemRealHostIntegrationTests/testConfigURLSkipsWhenNoIntegrationFileIsProvided`

Expected: FAIL because current code falls back to a committed real-host fixture.

- [x] **Step 3: Remove default real-host fallback**

Change `configURL(environment:)` so it only uses `WETRANS_SFTP_INTEGRATION_FILE`; otherwise it throws `XCTSkip("Set WETRANS_SFTP_INTEGRATION_FILE or run scripts/e2e to start the local Docker SFTP fixture.")`.

- [x] **Step 4: Use auth helper in connect/list and transfer tests**

Replace inline `.sshKey(...)` construction with `host.auth(environment: environment)` in both `smoke` and `transferE2E`.

- [x] **Step 5: Run green focused tests**

Run: `swift test --filter RemoteFileSystemRealHostIntegrationTests`

Expected: PASS with live tests skipped when no env config is provided, and config decoding tests passing.

### Task 3: Add local Docker OpenSSH fixture script

**Files:**
- Create: `scripts/local-sftp-fixture`
- Modify: `scripts/e2e`

- [x] **Step 1: Create fixture script**

Create an executable Bash script that:

- checks Docker CLI and daemon
- creates a temporary work directory
- generates an ed25519 key
- generates a random password without printing it
- starts `lscr.io/linuxserver/openssh-server:latest`
- binds `127.0.0.1::<2222>` dynamically
- waits for the host port to accept TCP
- writes a two-host JSON config
- exports `WETRANS_SFTP_INTEGRATION_FILE` and `WETRANS_SFTP_FIXTURE_PASSWORD`
- executes the command after `--`
- removes the container and temp dir on exit

- [x] **Step 2: Wire `scripts/e2e` through the fixture**

Replace direct `swift test --filter RemoteFileSystemRealHostIntegrationTests` with:

```bash
"$ROOT/scripts/local-sftp-fixture" -- swift test --filter RemoteFileSystemRealHostIntegrationTests
```

- [x] **Step 3: Verify executable bit**

Run: `test -x scripts/local-sftp-fixture`

Expected: exit 0.

### Task 4: Validate Docker fixture against current tests

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-local-docker-sftp-e2e.md`

- [x] **Step 1: Run fixture-backed SFTP tests**

Run: `scripts/local-sftp-fixture -- swift test --filter RemoteFileSystemRealHostIntegrationTests`

Expected: PASS; key and password hosts both run connect/list/upload/download.

- [x] **Step 2: Run non-Docker test path**

Run: `scripts/test`

Expected: PASS; live SFTP tests skip without `WETRANS_SFTP_INTEGRATION_FILE`.

- [x] **Step 3: Run typecheck**

Run: `scripts/typecheck`

Expected: PASS.

### Task 5: Update docs and workflow text

**Files:**
- Modify: `README.md`
- Modify: `docs/README.md`
- Modify: `docs/real-host-sftp-smoke.md`
- Modify: `docs/architecture-design.md`
- Modify: `docs/implementation-plan.md`
- Modify: `.codebuddy/rules/testing.mdc`
- Modify: `scripts/setup`

- [x] **Step 1: Replace default real-host wording**

Update docs to say default SFTP E2E uses local Docker OpenSSH and external hosts are opt-in only.

- [x] **Step 2: Remove default `openclaw-vm` setup requirement**

Update setup/testing docs so `openclaw-vm` and `~/.ssh/openclaw_vm` are not required for default verification.

- [x] **Step 3: Document Docker requirement**

Add the Docker daemon requirement for `scripts/e2e` and `scripts/verify`.

- [x] **Step 4: Run documentation sanity checks**

Run: `grep -R "openclaw-vm.*default\|committed \\`openclaw-vm\\` key\|requires.*openclaw" README.md docs .codebuddy/rules scripts/setup || true`

Expected: no stale default-path wording.

### Task 6: Final verification

**Files:**
- Modify: `docs/superpowers/plans/2026-06-27-local-docker-sftp-e2e.md`

- [x] **Step 1: Run diff checks**

Run: `git diff --check`

Expected: PASS.

- [x] **Step 2: Run full available verification**

Run: `scripts/verify`

Expected: SFTP Docker fixture and tests pass; UI E2E may still require macOS Accessibility permission. If Accessibility blocks app smoke, record the exact blocker.

- [x] **Step 3: Mark plan complete**

Update this plan's checkboxes for completed steps.

No commit step is included because commits require an explicit user request in this environment.

## Execution Notes

- Implemented inline in this session because the available subagent is optimized for code exploration, not implementation.
- `scripts/local-sftp-fixture -- swift test --filter wetransTests.RemoteFileSystemRealHostIntegrationTests` passed: 4 tests, 0 failures.
- `scripts/test` passed: 182 tests, 2 skipped, 0 failures. The skipped tests are live SFTP tests when `WETRANS_SFTP_INTEGRATION_FILE` is not provided outside the Docker fixture.
- `scripts/typecheck` passed.
- `git diff --check` passed.
- `scripts/e2e` and `scripts/verify` reached native UI E2E and are blocked by macOS Accessibility permission: `Accessibility permission is required for native UI E2E`.
- Docker fixture cleanup verified with no remaining `wetrans-openssh-e2e-*` containers.
