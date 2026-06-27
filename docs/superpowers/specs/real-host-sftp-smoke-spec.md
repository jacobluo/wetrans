# Real Host SFTP Integration Spec

## Purpose

wetrans has regressed multiple times in ways that compile and pass fake-client tests but fail to open real remote directories. Add an explicit, opt-in integration test that connects to a known development host through the same libssh2-backed SFTP path used by the app.

## Host

The committed fixture currently covers:

- `openclaw-vm`

This host is a development integration target. Its private key and passphrase must never be committed.

## Scope

- Merge the fixed real-host connect/list coverage into `LibSSH2RemoteFileSystemIntegrationTests`.
- Add a skipped-by-default XCTest that reads a JSON host list.
- Include a committed example fixture with non-secret host metadata and local identity-file paths.
- Allow `WETRANS_SFTP_INTEGRATION_FILE` to override the committed fixture.
- Run each configured host independently through `LibSSH2RemoteFileSystem.connect`, `listDirectory`, and `disconnect`.
- Produce host-specific failure messages that include host name and list path.
- Document the config format and secret handling.

## Out of Scope

- Running real host tests from default `scripts/verify`.
- UI automation for host selection.
- Upload/download transfer checks.
- Storing or reading app Keychain credentials.
- Committing passwords, passphrases, private key contents, or `.env` files.
- `xfh-cmg-es` coverage. Add it back only after the one-host path is stable.

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

Rules:

- Do not put passwords, private key contents, passphrases, tokens, or authorization headers in this file.
- `identityFile` is a local filesystem path only.
- `~` expands to the current user's home directory.
- If host key fields are absent, the test may trust the first key in a temporary trusted-host store for that test run only.

## Running

Default `swift test` should skip real host access.

Run the integration test explicitly:

```bash
WETRANS_RUN_SFTP_INTEGRATION=1 swift test --filter LibSSH2RemoteFileSystemIntegrationTests
```

Use an override config:

```bash
WETRANS_RUN_SFTP_INTEGRATION=1 \
WETRANS_SFTP_INTEGRATION_FILE=/Users/robiluo/.config/wetrans/real-sftp-integration.json \
swift test --filter LibSSH2RemoteFileSystemIntegrationTests
```

## Acceptance Criteria

- The committed fixture decodes and contains `openclaw-vm`.
- Default test runs skip real host access.
- Opt-in test connects and lists every configured host with libssh2 SFTP.
- Failures identify the host name, hostname, and list path.
- No committed file contains secrets.
- `scripts/verify` passes with the integration test skipped.
