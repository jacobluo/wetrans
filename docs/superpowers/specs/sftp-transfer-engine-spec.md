# SFTP Transfer Engine Spec

## Purpose

wetrans already has a global transfer queue and real SFTP connect/listing. This slice connects the two by adding upload/download operations to the remote file-system boundary and implementing a libssh2-backed `TransferEngine`.

## Product Boundary

This slice enables real single-file upload and download execution behind `TransferQueue`. Multi-file behavior is already represented as one queue task per file; the queue can run several of those tasks concurrently.

## In Scope

- Add upload/download request models.
- Extend `RemoteFileSystem` with upload and download methods.
- Extend `LibSSH2Client` with blocking SFTP upload/download methods.
- Add libssh2 dynamic symbols for `libssh2_sftp_read` and `libssh2_sftp_write`.
- Implement local-file read/write loops with progress callbacks.
- Implement `SFTPTransferEngine` as a `TransferEngine`.
- Open one SFTP connection per transfer task through a connection provider, avoiding shared SFTP handles across concurrent queue jobs.
- Support cancellation checks between chunks.
- Map local and remote file errors into readable thrown errors.
- Add opt-in integration coverage for upload/download when real SFTP credentials are provided.

## Out of Scope

- Drag-and-drop UI.
- Upload/download toolbar buttons.
- File conflict prompts.
- Folder upload/download.
- Resume/pause.
- Remote directory refresh callbacks after success.
- Progress UI beyond existing queue summary.

## Design

### Request Models

```swift
public struct UploadRequest: Equatable, Sendable {
    public let localPath: String
    public let remotePath: String
}

public struct DownloadRequest: Equatable, Sendable {
    public let remotePath: String
    public let localPath: String
}
```

Both requests represent a single file.

### RemoteFileSystem

```swift
public protocol RemoteFileSystem {
    func connect(_ spec: ConnectionSpec) async throws -> RemoteSession
    func disconnect(_ session: RemoteSession) async
    func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem]
    func upload(_ request: UploadRequest, in session: RemoteSession, progress: @escaping @Sendable (TransferProgress) async -> Void) async throws
    func download(_ request: DownloadRequest, in session: RemoteSession, progress: @escaping @Sendable (TransferProgress) async -> Void) async throws
}
```

### Transfer Engine

`SFTPTransferEngine` converts `TransferTask` into upload/download requests:

- `.upload`: read `task.localPath`, write `task.remotePath`
- `.download`: read `task.remotePath`, write `task.localPath`

The engine must not reuse the currently browsed host session. It receives a connection provider that can create a new `RemoteSession` for a task host and then disconnect it when the transfer finishes.

## Concurrency Rule

Each running transfer gets its own remote session. This keeps concurrent queue jobs from sharing a libssh2 SFTP handle.

## Error Handling

Use readable error messages:

- local file does not exist
- local path is not a regular file for upload
- local destination cannot be created for download
- remote open/read/write fails
- transfer is cancelled
- host cannot be resolved for task

The queue stores these messages in `TransferTask.errorMessage`.

## Acceptance Criteria

- Upload tasks invoke remote upload with progress.
- Download tasks invoke remote download with progress.
- `LibSSH2RemoteFileSystem` delegates upload/download to its session client.
- Missing session upload/download throws `RemoteFileSystemError.disconnected`.
- Dynamic libssh2 client writes local bytes to remote using `libssh2_sftp_write`.
- Dynamic libssh2 client reads remote bytes to local using `libssh2_sftp_read`.
- Cancellation is checked during upload/download loops.
- `SFTPTransferEngine` opens and closes one remote session per task.
- Unit tests cover upload, download, progress, cancellation, and disconnected errors.
- `swift test` and `swift build` pass.
