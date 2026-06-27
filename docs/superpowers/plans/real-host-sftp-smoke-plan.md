# Real Host SFTP Smoke Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add an opt-in real host smoke test that verifies libssh2 can connect to and list remote directories for `openclaw-vm` and `xfh-cmg-es`.

**Architecture:** Keep real host testing inside XCTest and off the default verification path. A small Decodable config model in the test file reads a committed non-secret fixture or a `WETRANS_REAL_HOSTS_FILE` override, builds `ConnectionSpec` values with local identity-file paths, and exercises `LibSSH2RemoteFileSystem`.

**Tech Stack:** Swift 6, SwiftPM XCTest, JSONDecoder, existing `LibSSH2RemoteFileSystem`, existing opt-in environment-variable pattern.

---

### Task 1: Fixture, Docs, And Config Decoder

**Files:**
- Create: `docs/superpowers/specs/real-host-sftp-smoke-spec.md`
- Create: `docs/superpowers/plans/real-host-sftp-smoke-plan.md`
- Create: `docs/real-host-sftp-smoke.md`
- Create: `wetransTests/Fixtures/real-host-smoke.example.json`
- Create: `wetransTests/RemoteFileSystem/RealHostSFTPSmokeTests.swift`
- Modify: `Package.swift`
- Modify: `README.md`

- [x] **Step 1: Add committed example fixture**

Create `wetransTests/Fixtures/real-host-smoke.example.json` with `openclaw-vm` and `xfh-cmg-es` host metadata only. Do not include passwords, private key contents, passphrases, tokens, or authorization headers.

- [x] **Step 2: Add docs**

Create `docs/real-host-sftp-smoke.md` explaining purpose, config format, field requirements, secret handling, and run commands. Add a short README link near existing optional integration probes.

- [x] **Step 3: Write config decoding test**

Create `RealHostSFTPSmokeTests` with a test that decodes the committed fixture and asserts it contains `openclaw-vm` and `xfh-cmg-es`.

- [x] **Step 4: Run decoding test**

Run: `swift test --filter RealHostSFTPSmokeTests/testCommittedFixtureDecodesExpectedHosts`

Expected: PASS.

### Task 2: Opt-In Real Host Smoke

**Files:**
- Modify: `wetransTests/RemoteFileSystem/RealHostSFTPSmokeTests.swift`
- Modify: `docs/superpowers/plans/real-host-sftp-smoke-plan.md`

- [x] **Step 1: Add skipped-by-default smoke test**

Add `testConfiguredRealHostsConnectAndListWhenEnabled`. It should skip unless `WETRANS_RUN_REAL_HOST_SMOKE=1`.

- [x] **Step 2: Implement config resolution**

Use `WETRANS_REAL_HOSTS_FILE` when set; otherwise use `wetransTests/Fixtures/real-host-smoke.example.json`.

- [x] **Step 3: Implement per-host connect/list/disconnect**

For each configured host, expand `~` in `identityFile`, read passphrase from `passphraseEnv` if present, build `ConnectionSpec`, connect with `LibSSH2RemoteFileSystem`, list `listPath`, and disconnect. If a host key requires trust and no host key is preconfigured, trust only in the temporary test store and retry.

- [x] **Step 4: Run default skip verification**

Run: `swift test --filter RealHostSFTPSmokeTests/testConfiguredRealHostsConnectAndListWhenEnabled`

Expected: PASS with the test skipped.

- [x] **Step 5: Run full verification**

Run: `scripts/verify`

Expected: PASS with real host smoke skipped.

- [x] **Step 6: Run opt-in real host smoke**

Run: `WETRANS_RUN_REAL_HOST_SMOKE=1 swift test --filter RealHostSFTPSmokeTests/testConfiguredRealHostsConnectAndListWhenEnabled`

Expected: PASS for the configured real hosts.

- [x] **Step 7: Commit**

Run:

```bash
git add Package.swift README.md docs/superpowers/specs/real-host-sftp-smoke-spec.md docs/superpowers/plans/real-host-sftp-smoke-plan.md docs/real-host-sftp-smoke.md wetransTests/Fixtures/real-host-smoke.example.json wetransTests/RemoteFileSystem/RealHostSFTPSmokeTests.swift
git commit -m "test: add real host SFTP smoke"
```
