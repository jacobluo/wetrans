# Real Host SFTP Integration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in real host integration test that verifies libssh2 can connect to and list remote directories for `openclaw-vm`.

**Architecture:** Keep real host testing inside XCTest and off the default verification path. A small Decodable config model in `LibSSH2RemoteFileSystemIntegrationTests` reads a committed non-secret fixture or a `WETRANS_SFTP_INTEGRATION_FILE` override, builds `ConnectionSpec` values with local identity-file paths, and exercises `LibSSH2RemoteFileSystem`.

**Tech Stack:** Swift 6, SwiftPM XCTest, JSONDecoder, existing `LibSSH2RemoteFileSystem`, existing opt-in environment-variable pattern.

---

### Task 1: Fixture, Docs, And Config Decoder

**Files:**
- Create: `docs/superpowers/specs/real-host-sftp-smoke-spec.md`
- Create: `docs/superpowers/plans/real-host-sftp-smoke-plan.md`
- Create: `docs/real-host-sftp-smoke.md`
- Create: `wetransTests/Fixtures/real-host-smoke.example.json`
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Modify: `Package.swift`
- Modify: `README.md`

- [x] **Step 1: Add committed example fixture**

Create `wetransTests/Fixtures/real-host-smoke.example.json` with `openclaw-vm` host metadata only. Do not include passwords, private key contents, passphrases, tokens, or authorization headers.

- [x] **Step 2: Add docs**

Create `docs/real-host-sftp-smoke.md` explaining purpose, config format, field requirements, secret handling, and run commands. Add a short README link near existing optional integration probes.

- [x] **Step 3: Write config decoding test**

Add `LibSSH2RemoteFileSystemIntegrationTests` fixture decoding coverage that asserts the committed fixture contains `openclaw-vm`.

- [x] **Step 4: Run decoding test**

Run: `swift test --filter LibSSH2RemoteFileSystemIntegrationTests/testCommittedFixtureDecodesOpenclawVM`

Expected: PASS.

### Task 2: Opt-In Real Host Integration

**Files:**
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Modify: `docs/superpowers/plans/real-host-sftp-smoke-plan.md`

- [x] **Step 1: Add skipped-by-default integration test**

Add `testConfiguredRealHostsConnectAndListWhenEnabled`. It should skip unless `WETRANS_RUN_SFTP_INTEGRATION=1`.

- [x] **Step 2: Implement config resolution**

Use `WETRANS_SFTP_INTEGRATION_FILE` when set; otherwise use `wetransTests/Fixtures/real-host-smoke.example.json`.

- [x] **Step 3: Implement per-host connect/list/disconnect**

For each configured host, expand `~` in `identityFile`, read passphrase from `passphraseEnv` if present, build `ConnectionSpec`, connect with `LibSSH2RemoteFileSystem`, list `listPath`, and disconnect. If a host key requires trust and no host key is preconfigured, trust only in the temporary test store and retry.

- [x] **Step 4: Run default skip verification**

Run: `swift test --filter LibSSH2RemoteFileSystemIntegrationTests/testConfiguredRealHostsConnectAndListWhenEnabled`

Expected: PASS with the test skipped.

- [x] **Step 5: Run full verification**

Run: `scripts/verify`

Expected: PASS with real host integration skipped.

- [x] **Step 6: Run opt-in real host integration**

Run: `WETRANS_RUN_SFTP_INTEGRATION=1 swift test --filter LibSSH2RemoteFileSystemIntegrationTests/testConfiguredRealHostsConnectAndListWhenEnabled`

Expected: PASS for the configured real host.
