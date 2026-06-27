# Real Host SFTP E2E

The real host SFTP E2E tests verify that wetrans can connect to known development hosts, list remote directories, upload files, and download files through the same libssh2-backed SFTP path used by the app.

These tests run by default because real remote transfer access is part of the required verification path. They depend on network access, reachable hosts, and local private key files.

## Coverage

`RemoteFileSystemRealHostIntegrationTests` covers:

- fixture decoding for the committed non-secret host metadata
- connect and list for every configured host
- upload one file
- upload multiple files
- upload a directory that contains a nested child directory
- download one file
- download multiple files
- download a directory that contains a nested child directory

Download fixtures are created by the same test run. The tests upload deterministic local files to a unique remote `/tmp/wetrans-e2e-<uuid>/` root, download them into a separate local temporary directory, and compare file contents byte-for-byte. No manual remote fixture preparation is required.

## Run

Use the committed non-secret fixture:

```bash
swift test --filter RemoteFileSystemRealHostIntegrationTests
```

Run the default E2E path:

```bash
scripts/e2e
```

`scripts/e2e` runs the real-host SFTP E2E suite first, then builds and launches the packaged app for native UI smoke verification.

Use a local override config:

```bash
WETRANS_SFTP_INTEGRATION_FILE=/path/to/local-real-sftp-integration.json \
swift test --filter RemoteFileSystemRealHostIntegrationTests
```

## Config Format

```json
{
  "hosts": [
    {
      "name": "openclaw-vm",
      "hostname": "43.164.133.39",
      "port": 22,
      "username": "ubuntu",
      "identityFile": "~/.ssh/openclaw_vm",
      "listPath": ".",
      "passphraseEnv": "WETRANS_OPENCLAW_KEY_PASSPHRASE",
      "hostKeyType": "ssh-ed25519",
      "hostKeyFingerprintSHA256": "SHA256:..."
    }
  ]
}
```

Required fields:

- `name`
- `hostname`
- `port`
- `username`
- `identityFile`
- `listPath`

Optional fields:

- `passphraseEnv`: environment variable name containing the private key passphrase.
- `hostKeyType`: trusted host key type for pre-seeding trust.
- `hostKeyFingerprintSHA256`: trusted host key fingerprint for pre-seeding trust.

## Secret Handling

Do not put passwords, private key contents, passphrases, tokens, authorization headers, or `.env` files in this repo.

`identityFile` is only a local filesystem path. The test expands `~` to the current user's home directory. If a private key passphrase is needed, store it in an environment variable and reference the variable name with `passphraseEnv`.

If `hostKeyType` and `hostKeyFingerprintSHA256` are absent, the test trusts the first observed host key only in a temporary test store for that test run.

## Committed Fixture

The committed fixture is:

```text
wetransTests/Fixtures/real-host-smoke.example.json
```

It currently covers:

- `openclaw-vm`

Use `WETRANS_SFTP_INTEGRATION_FILE` if your local key paths differ.
