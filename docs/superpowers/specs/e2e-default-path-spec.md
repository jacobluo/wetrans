# E2E Default Path Spec

Status: Draft for review

## 1. Purpose

wetrans needs one default E2E entry point that proves two things before internal testing:

- the real SFTP implementation can connect, list, upload, and download against the OpenCloud development VM
- the packaged macOS app can build, launch, and render the main UI surfaces used by file transfer workflows

This spec extends the existing E2E infrastructure instead of replacing unit tests. The default path should catch failures that fake-client unit tests cannot see while keeping UI automation stable enough to run often.

## 2. Product Boundary

The default E2E suite has two layers:

1. Real Host SFTP E2E
2. App Build and Run Smoke

The real-host layer exercises the libssh2-backed SFTP path directly through test code. It is not a UI-click-through transfer test. Full UI transfer automation remains gated behind explicit environment variables and can evolve separately.

The app smoke layer verifies that a packaged app can launch and expose core UI accessibility anchors. It does not perform a real host connection through the UI in this slice.

## 3. Real Host SFTP E2E

The real-host layer uses the existing non-secret host fixture and local override support:

- committed example fixture: `wetransTests/Fixtures/real-host-smoke.example.json`
- override: `WETRANS_SFTP_INTEGRATION_FILE`

For each configured host, the test suite should cover:

- connect and list the configured `listPath`
- upload one file
- upload multiple files
- upload a directory
- download one file
- download multiple files
- download a directory

All writable remote data must live under a unique temporary root:

```text
/tmp/wetrans-e2e-<uuid>/
```

No test may require manually prepared remote files. Download fixtures are created by the same test run, preferably by uploading deterministic local source files first and then downloading them back into a separate local temporary directory.

## 4. Transfer Fixture Shape

The fixture should be small, deterministic, and explicit enough to catch path-preservation bugs:

```text
source/
  single.txt
  multi-a.txt
  multi-b.txt
  folder/
    root-a.txt
    nested/
      nested-a.txt
      nested-b.txt
```

The directory tests must include the `nested/` child directory. This verifies that directory upload and download preserve subdirectory structure, not only top-level files.

Suggested remote layout:

```text
/tmp/wetrans-e2e-<uuid>/
  uploads/
    single/
    multiple/
    directory/
  downloads/
    single/
    multiple/
    directory/
```

The exact layout may differ as long as every test uses a unique root and assertions compare the expected file names, relative paths, and file contents.

## 5. App Build and Run Smoke

The app smoke layer should keep using the existing native macOS E2E runner:

- build/package the app using the repository packaging path
- launch the app
- inspect the running app through macOS Accessibility
- verify these core anchors exist:
  - `Connect Host`
  - `Local File Panel`
  - `Remote File Panel`
  - `Transfer Queue`

This is a smoke test, not a full UI workflow. Its job is to prove the app starts and the main transfer UI is available for automation.

## 6. Script Behavior

`scripts/e2e` should become the single E2E entry point:

```text
scripts/e2e
  -> Real Host SFTP E2E
  -> App Build and Run Smoke
  -> optional full UI E2E scenarios when WETRANS_E2E_RUN_FULL=1
```

Default behavior should run real-host connect/list and transfer checks plus app smoke. If the host fixture is unavailable or credentials are missing, failure should be explicit and should explain which fixture or local key path needs attention.

The existing full UI scenarios remain gated because they depend on Accessibility permission, local SSH config state, and environment-provided host details.

## 7. Secret and Safety Rules

- Do not commit private keys, passphrases, passwords, tokens, `.env` files, or authorization headers.
- Test fixture files may contain host metadata and local identity-file paths only.
- Passphrases must be read through environment variables referenced by name.
- Remote writes must stay under `/tmp/wetrans-e2e-<uuid>/`.
- Tests should avoid deleting any path that does not begin with the generated temporary root.
- Failure output may include host names and temporary paths, but must not print credential values.

## 8. Acceptance Criteria

- `scripts/e2e` runs real-host SFTP E2E by default.
- Real-host E2E covers connect/list.
- Real-host E2E covers upload single file, multiple files, and directory with a nested child directory.
- Real-host E2E covers download single file, multiple files, and directory with a nested child directory.
- Download tests create their own remote fixtures during the same test run and do not require manual remote setup.
- App build and run smoke still launches the packaged app and checks the main UI accessibility anchors.
- Full UI E2E scenarios remain opt-in behind `WETRANS_E2E_RUN_FULL=1`.
- `scripts/verify` includes the updated `scripts/e2e` path.
