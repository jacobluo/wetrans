# SFTP Transfer Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add real SFTP upload/download execution behind the existing transfer queue.

**Architecture:** Extend the `RemoteFileSystem` and `LibSSH2Client` boundaries with single-file upload/download operations. Add `SFTPTransferEngine` to adapt `TransferTask` into a fresh remote session per transfer, so concurrent queue jobs do not share SFTP handles.

**Tech Stack:** Swift 6, Swift concurrency, Foundation file I/O, libssh2 dynamic symbols, XCTest.

---

## File Structure

- Create `wetrans/RemoteFileSystem/TransferRequests.swift`: `UploadRequest` and `DownloadRequest`.
- Modify `wetrans/RemoteFileSystem/RemoteFileSystem.swift`: add upload/download protocol methods and error cases.
- Modify `wetrans/RemoteFileSystem/MockRemoteFileSystem.swift`: test support for upload/download calls.
- Modify `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`: route upload/download to connected clients.
- Modify `wetrans/RemoteFileSystem/LibSSH2Client.swift`: add upload/download client requirements.
- Modify `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`: add dynamic SFTP read/write loops.
- Create `wetrans/TransferQueue/SFTPTransferEngine.swift`: bridge queue tasks to remote file system transfers.
- Test `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`: protocol delegation and disconnected errors.
- Test `wetransTests/RemoteFileSystem/LibSSH2DynamicClientTests.swift`: request path/error helper logic.
- Test `wetransTests/TransferQueue/SFTPTransferEngineTests.swift`: session lifecycle and task direction mapping.

## Task 1: Remote Upload/Download Boundary

- [x] Write failing tests for `LibSSH2RemoteFileSystem.upload/download` delegation and disconnected errors.
- [x] Run `swift test --filter LibSSH2RemoteFileSystemTests` and confirm failure.
- [x] Add request models, protocol methods, fake client support, and adapter delegation.
- [x] Re-run `swift test --filter LibSSH2RemoteFileSystemTests`.

## Task 2: SFTPTransferEngine

- [x] Write failing tests for upload task mapping, download task mapping, progress forwarding, and disconnect-after-failure.
- [x] Run `swift test --filter SFTPTransferEngineTests` and confirm failure.
- [x] Implement `SFTPTransferEngine` with a host connection provider.
- [x] Re-run `swift test --filter SFTPTransferEngineTests`.

## Task 3: libssh2 Read/Write Loops

- [x] Write failing unit tests for helper behavior where practical.
- [x] Add `libssh2_sftp_read` and `libssh2_sftp_write` symbols.
- [x] Implement upload: open local file, open remote file with create/truncate/write flags, write chunks, emit progress.
- [x] Implement download: open remote file for read, create parent directory, write chunks locally, emit progress.
- [x] Add/update opt-in integration test notes for real upload/download.
- [x] Run relevant remote file-system tests.

## Final Verification

- [x] Run `swift test`
- [x] Run `swift build`
- [x] Commit, push, and open PR.
