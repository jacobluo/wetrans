# Directory Transfers Spec

## 1. Purpose

Drag-and-drop is no longer the next usability priority. wetrans should first support selecting a directory and uploading or downloading the files under that directory while preserving the directory tree.

## 2. Product Boundary

This slice replaces the near-term drag-and-drop backlog item with directory-level upload and download through the existing toolbar and context-menu transfer actions.

It does not add drag-and-drop gestures, conflict prompts, resumable transfers, directory sync, remote file mutation UI, or a new batch-task persistence schema.

## 3. User Behavior

When a user selects a local directory and clicks Upload:

- wetrans recursively scans the selected local directory.
- The top-level directory name is preserved.
- Each regular file becomes one `TransferTask`.
- The remote destination is the current remote panel path plus the selected directory name.

Example:

```text
Local:  /Users/me/Downloads/site
Remote: /var/www
Result: /var/www/site/...
```

When a user selects a remote directory and clicks Download:

- wetrans recursively lists the selected remote directory.
- The top-level directory name is preserved.
- Each regular file becomes one `TransferTask`.
- The local destination is the current local panel path plus the selected directory name.

Example:

```text
Remote: /var/log/nginx
Local:  /Users/me/Downloads
Result: /Users/me/Downloads/nginx/...
```

## 4. Implementation Decisions

- Keep one `TransferTask` per file.
- Reuse the existing transfer queue, concurrency limits, progress, cancel, retry, history, and refresh behavior.
- Skip symlink directories during recursion.
- Treat symlink files as files only when the existing file-system listing marks them as non-directories.
- Skip empty directories in this first slice because the current queue model has no directory-only task.
- Create remote parent directories automatically before each uploaded file.
- Create local parent directories automatically before each downloaded file; the current download implementation already does this.
- Directory transfer failure during planning should surface as a panel error and should not enqueue a partial set of tasks.

## 5. Module Changes

- Add a directory transfer planner that expands local or remote directory selections into file transfer tasks.
- Add `HostSessionManager.listRemoteDirectory(path:for:)` so recursive remote scanning can list arbitrary child paths without mutating the visible remote panel path.
- Add `RemoteFileSystem.ensureDirectory(_ path:in:)` so upload execution can create remote parent directories.
- Add `LibSSH2Client.ensureDirectory(_:)` and a libssh2-backed implementation using `libssh2_sftp_mkdir_ex`.

## 6. UI Changes

- Toolbar upload/download buttons become enabled when the selection contains files or directories.
- Context upload/download actions become enabled for files and directories.
- Existing selection behavior remains unchanged.
- Existing error surfaces are reused.

## 7. Acceptance Criteria

- Uploading a selected local directory enqueues one task per contained file and preserves the top-level directory name.
- Downloading a selected remote directory enqueues one task per contained file and preserves the top-level directory name.
- Selected files and selected directories can be mixed in one enqueue action.
- Symlink directories are not recursively traversed.
- Remote parent directories are ensured before upload execution.
- Empty directories are skipped and do not create transfer tasks.
- Drag-and-drop references are removed from near-term productization docs.
- `scripts/verify` passes.
