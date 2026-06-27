# Real Host SFTP Smoke

The real host SFTP smoke test verifies that wetrans can connect to known development hosts and list remote directories through the same libssh2-backed SFTP path used by the app.

This test is skipped by default because it depends on network access, reachable hosts, and local private key files.

## Run

Use the committed non-secret fixture:

```bash
WETRANS_RUN_REAL_HOST_SMOKE=1 swift test --filter RealHostSFTPSmokeTests
```

Use a local override config:

```bash
WETRANS_RUN_REAL_HOST_SMOKE=1 \
WETRANS_REAL_HOSTS_FILE=/Users/robiluo/.config/wetrans/real-host-smoke.json \
swift test --filter RealHostSFTPSmokeTests
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

`identityFile` is only a local filesystem path. The smoke test expands `~` to the current user's home directory. If a private key passphrase is needed, store it in an environment variable and reference the variable name with `passphraseEnv`.

If `hostKeyType` and `hostKeyFingerprintSHA256` are absent, the smoke test trusts the first observed host key only in a temporary test store for that test run.

## Committed Fixture

The committed fixture is:

```text
wetransTests/Fixtures/real-host-smoke.example.json
```

It currently covers:

- `openclaw-vm`
- `xfh-cmg-es`

Use `WETRANS_REAL_HOSTS_FILE` if your local key paths differ.
