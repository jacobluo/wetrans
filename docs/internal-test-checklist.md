# wetrans Internal Test Checklist

Use this checklist for internal builds before broader UI E2E and drag-and-drop work. Do not put passwords, passphrases, private key contents, or tokens in bug reports.

## 1. Build and Launch

- Run `scripts/package --verify`.
- Launch `dist/wetrans.app`.
- Confirm the main three-pane browser opens.
- Confirm the host sidebar, local file panel, remote file panel, and transfer queue are visible.

## 2. Host Onboarding

- Add a manual host.
- If available, add a host from SSH Config.
- Confirm saved hosts appear in the sidebar.
- Edit a saved host display name.
- Favorite and unfavorite a saved host.
- Delete a disposable saved host and confirm it disappears.

## 3. Browsing

- Select a saved host.
- Browse the default local directory.
- Enter a local path manually.
- Refresh the local panel.
- Connect to the remote host.
- Confirm unknown host-key trust prompts appear when expected.
- Browse the default remote path.
- Enter a remote path manually.
- Refresh the remote panel.
- Switch hosts and confirm local/remote paths are remembered.

## 4. Transfers

- Select one local file and upload it.
- Select multiple local files and upload them.
- Select one remote file and download it.
- Select multiple remote files and download them.
- Confirm successful uploads refresh the visible remote directory.
- Confirm successful downloads refresh the visible local directory.
- Expand the transfer queue.
- Cancel a pending or running disposable transfer when practical.
- Retry a failed or cancelled disposable transfer.
- Clear terminal transfer rows.

## 5. Diagnostics

- When a local or remote panel shows `Could Not Load`, click `Copy Debug Detail`.
- Paste the debug detail into the bug report.
- Confirm copied detail includes panel, path, message, and host when relevant.
- Confirm copied detail does not include passwords, passphrases, or private key contents.
- For transfer failures, use the queue row's copy-error action.
- Include the app version or commit, macOS version, auth type, and whether the host came from manual entry or SSH Config generation.

## 6. Bug Report Shape

```text
Title:
Build or commit:
macOS version:
Host source: Manual / SSH Config generated
Auth type: Password / SSH key
Steps:
Expected:
Actual:
Copied debug detail:
Transfer queue error, if any:
Screenshots, if useful:
```

## 7. Stop Conditions

- Do not continue testing with production-only data after a host-key changed warning.
- Do not attach private keys, passwords, passphrases, `.env` files, or full shell history.
- Do not paste raw provider tokens or authorization headers into reports.
