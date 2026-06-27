# wetrans

wetrans is a native macOS SSH/SFTP remote file manager for people who move files between a Mac and remote Linux hosts.

It keeps the daily workflow close to Finder: pick a saved host, browse local and remote directories side by side, then upload or download selected files through a visible transfer queue.

## Screenshots

### Main Browser

![wetrans main browser ardot prototype](docs/assets/wetrans-ardot-main-browser.webp)

### Connect Host

![wetrans connect host ardot prototype](docs/assets/wetrans-ardot-connect-host.webp)

_Screenshots from the current ardot MVP prototype._

## What It Does

- Browse local files and remote SFTP directories in a three-pane macOS layout.
- Save hosts manually or generate saved hosts from `~/.ssh/config`.
- Treat SSH Config as an import source only; saved hosts become normal wetrans hosts.
- Store host metadata locally while keeping passwords and key passphrases in macOS Keychain.
- Verify and persist trusted host keys without modifying OpenSSH `known_hosts`.
- Upload and download files through a global transfer queue with bounded concurrency.
- Support single-click selection by default, with Shift-click multi-selection for batch transfers.
- Provide desktop-style row actions such as upload, download, reveal in Finder, copy remote path, and retry/remove transfer tasks.

## Current Status

wetrans is in MVP development. The current implementation is SwiftPM-first and targets native macOS distribution outside the Mac App Store during early internal testing.

The MVP intentionally focuses on direct SSH/SFTP file management. Advanced SSH runtime features such as ProxyJump, complex ProxyCommand, SSH Agent integration, keyboard-interactive auth, recursive folder transfer, and resumable transfers are outside the first slice.

## Design Source

The UI direction comes from the ardot MVP prototype:

```text
cocraft://localhost/file/697398357828482?node_id=0%3A1
```

The target feel is macOS-native: Finder-like host navigation, AppKit table density, restrained controls, and a bottom transfer queue that stays visible while browsing.

## Local Development

Requirements:

- macOS
- Swift toolchain
- `libssh2` for real SSH/SFTP runtime work

Install the SFTP runtime dependency:

```bash
brew install libssh2
```

Set up and verify the project:

```bash
scripts/setup
scripts/verify
```

Common commands:

```bash
swift build
swift test
swift run wetrans
```

Optional real integration probes are disabled by default because they require local environment setup and real SSH credentials:

```bash
WETRANS_RUN_LIBSSH2_REAL_PROBE=1 swift test --filter LibSSH2RuntimeRealProbeTests
WETRANS_RUN_SFTP_INTEGRATION=1 swift test --filter LibSSH2RemoteFileSystemIntegrationTests
WETRANS_RUN_REAL_HOST_SMOKE=1 swift test --filter RealHostSFTPSmokeTests
```

See [`docs/real-host-sftp-smoke.md`](docs/real-host-sftp-smoke.md) for the real host smoke config format and secret handling rules.

## Project Docs

Detailed product and engineering docs live under [`docs/`](docs/README.md), including the PRD, architecture design, data model, technical selection, and focused Superpowers specs.
