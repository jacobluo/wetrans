# Transfer Actions Spec

## Purpose

wetrans can browse files, maintain a global transfer queue, and execute SFTP transfers. This slice added the first user-facing transfer actions in the three-pane browser: upload selected local files and download selected remote files. Directory selections are now covered by `directory-transfers-spec.md`.

## Product Boundary

This slice created one `TransferTask` per selected file and enqueued those tasks into the global queue. It does not implement drag-and-drop, conflict handling, or expanded queue management. Folder transfer behavior is now implemented by `directory-transfers-spec.md`.

## In Scope

- Select files in local and remote file panels.
- Add upload/download toolbar buttons in file panels.
- Upload selected local regular files to the current remote directory.
- Download selected remote regular files to the current local directory.
- Create one transfer task per selected file.
- Use selected host id and display name on every task.
- Use local and remote panel paths to calculate destination paths.
- Directory selections are recursively expanded by the later directory transfer slice.
- Refresh transfer queue summary after enqueue.
- Show a readable browser error when no host or no files are selected.

## Out of Scope

- Drag-and-drop transfer.
- Context menus.
- Directory upload/download in this original slice; see `directory-transfers-spec.md`.
- File conflict prompts.
- Expanded queue table actions.
- Automatic refresh after task completion.

## UI Behavior

Local panel:

- shows an upload button when a host is selected
- button is enabled when at least one local file or directory is selected
- clicking upload enqueues upload tasks to the current remote path

Remote panel:

- shows a download button when a host is selected
- button is enabled when at least one remote file or directory is selected
- clicking download enqueues download tasks to the current local path

## Task Mapping

Upload:

```text
local selected file: /Users/me/config.yaml
remote panel path: /home/ubuntu/project
remote task path: /home/ubuntu/project/config.yaml
```

Download:

```text
remote selected file: /var/log/app.log
local panel path: /Users/me/Downloads
local task path: /Users/me/Downloads/app.log
```

## Acceptance Criteria

- Clicking a file selects it in its panel.
- Upload action enqueues one task per selected local file.
- Download action enqueues one task per selected remote file.
- Directories are recursively expanded by `DirectoryTransferPlanner`.
- Tasks use the currently selected host metadata.
- Tasks use correct local and remote paths.
- Queue summary updates after enqueue.
- The browser reports a readable error if upload/download cannot be started.
- `swift test` and `swift build` pass.
