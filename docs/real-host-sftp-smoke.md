# SFTP E2E Notes

This document is intentionally kept short. The default E2E direction has moved away from a fixed external real host and toward a local Docker-backed OpenSSH fixture.

Canonical spec:

```text
docs/superpowers/specs/local-docker-sftp-e2e-spec.md
```

## Default Path

The default SFTP E2E path should not require:

- `openclaw-vm`
- public network access
- `~/.ssh/openclaw_vm`
- any personal private key or passphrase

The intended default is:

```text
scripts/e2e
  -> start local Docker OpenSSH fixture
  -> generate temporary SFTP config
  -> run SFTP integration tests against 127.0.0.1:<dynamic-port>
  -> run packaged app smoke
```

The local fixture should use a general OpenSSH server image:

```text
lscr.io/linuxserver/openssh-server:latest
```

It should cover both authentication modes:

- SSH key authentication
- password authentication

## Coverage

The SFTP integration suite should continue to verify the real libssh2-backed path used by the app:

- connect and list
- upload one file
- upload multiple files
- upload a directory that contains a nested child directory
- download one file
- download multiple files
- download a directory that contains a nested child directory

Download fixtures are created by the same test run. The tests upload deterministic local files to a unique remote `/tmp/wetrans-e2e-<uuid>/` root, download them into a separate local temporary directory, and compare file contents byte-for-byte.

## External Host Override

External SFTP hosts are opt-in only. They are useful for manual validation against a specific cloud VM, but they are not part of the default verification path.

Use a local override config when needed:

```bash
WETRANS_SFTP_INTEGRATION_FILE=/path/to/external-sftp-config.json \
swift test --filter wetransTests.RemoteFileSystemRealHostIntegrationTests
```

Expected config shape:

```json
{
  "hosts": [
    {
      "name": "external-key-host",
      "hostname": "example.com",
      "port": 22,
      "username": "ubuntu",
      "identityFile": "~/.ssh/example_key",
      "listPath": ".",
      "passphraseEnv": "EXAMPLE_KEY_PASSPHRASE",
      "hostKeyType": "ssh-ed25519",
      "hostKeyFingerprintSHA256": "SHA256:..."
    },
    {
      "name": "external-password-host",
      "hostname": "example.com",
      "port": 22,
      "username": "ubuntu",
      "passwordEnv": "EXAMPLE_SFTP_PASSWORD",
      "listPath": "."
    }
  ]
}
```

## Secret Handling

Do not put passwords, private key contents, passphrases, tokens, authorization headers, or `.env` files in this repo.

Rules:

- `identityFile` is only a local filesystem path.
- `~` expands to the current user's home directory.
- Key passphrases must be read through `passphraseEnv`.
- Password auth must be read through `passwordEnv`.
- If `hostKeyType` and `hostKeyFingerprintSHA256` are absent, the test may trust the first observed host key only in a temporary test store for that test run.

## Historical Note

The previous default fixture pointed to `openclaw-vm`. That default is being retired because it depends on a specific external host, network reachability, and local credentials. Keep external host configs as local, opt-in files only.
