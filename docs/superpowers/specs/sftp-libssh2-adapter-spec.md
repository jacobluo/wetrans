# SFTP libssh2 Adapter Spec

Status: Draft for review
Parent PRD: `docs/prd.md`
Related docs:

- `docs/architecture-design.md`
- `docs/technical-selection.md`
- `docs/implementation-plan.md`
- `docs/superpowers/specs/remote-filesystem-foundation-spec.md`

## 1. Purpose

This spec retires the next SFTP integration risk without requiring a real SSH server or credentials in normal test runs.

It adds a libssh2 runtime/probe layer and a `RemoteFileSystem` adapter skeleton that can later grow into real SFTP connect/list/upload/download behavior.

The feature slice ends when wetrans can:

- Discover whether libssh2 is available.
- Load libssh2 dynamically when available.
- Read the libssh2 runtime version when symbols are present.
- Initialize and shut down libssh2 through a testable runtime boundary.
- Provide a `LibSSH2RemoteFileSystem` type that conforms to `RemoteFileSystem` and fails explicitly for not-yet-implemented real SFTP operations.

## 2. User Value

Users will not see new UI from this slice. The value is engineering risk reduction.

Before building the remote file browser and transfer queue on top of `RemoteFileSystem`, wetrans needs confidence that the native SFTP layer can be isolated, tested, and packaged without polluting UI code.

## 3. Scope

### 3.1 In Scope

- `LibSSH2LibraryInfo`.
- `LibSSH2LibraryLoading` protocol.
- Darwin dynamic library loader for libssh2.
- Candidate library path discovery.
- Environment override for library path.
- `LibSSH2Runtime`.
- Idempotent libssh2 initialization.
- libssh2 shutdown boundary.
- `LibSSH2RemoteFileSystem` skeleton conforming to `RemoteFileSystem`.
- Error mapping into app-level errors.
- Unit tests with fake loaders.
- Required real-library probe test.
- Documentation update explaining that dynamic probing is the first spike step.

### 3.2 Out of Scope

- Full SSH TCP connection.
- Password authentication.
- Public-key authentication.
- Host-key extraction.
- SFTP `opendir` / `readdir`.
- Upload.
- Download.
- Cancellation.
- AppKit UI.
- Real server integration tests that run by default.
- Committing local SSH credentials or server addresses.

## 4. Product Decisions

### 4.1 Dynamic Probe Before Hard Link

The first adapter slice dynamically probes libssh2 instead of hard-linking the app to Homebrew paths.

Reasons:

- Developer machines may not have libssh2 installed.
- Homebrew paths can vary.
- CI should run unit tests without native package setup.
- A dynamic boundary lets us test availability and error mapping cleanly.

Later packaging work may switch to a vendored or linked libssh2 distribution after the spike confirms behavior.

### 4.2 Environment Override

Development and CI can force a libssh2 path with:

```text
WETRANS_LIBSSH2_DYLIB=/path/to/libssh2.dylib
```

Default candidate paths:

```text
/opt/homebrew/opt/libssh2/lib/libssh2.dylib
/usr/local/opt/libssh2/lib/libssh2.dylib
/opt/homebrew/lib/libssh2.dylib
/usr/local/lib/libssh2.dylib
libssh2.dylib
```

### 4.3 Adapter Skeleton Must Fail Explicitly

`LibSSH2RemoteFileSystem.connect(_:)` should not pretend real SFTP works before authentication and host-key extraction exist.

For this slice, it may:

1. Initialize libssh2.
2. Throw a clear `.operationUnsupported("libssh2 SFTP connect is not implemented yet")` style error.

This keeps future UI from mistaking the skeleton for a working production adapter.

## 5. Module Design

### 5.1 LibSSH2LibraryInfo

```swift
struct LibSSH2LibraryInfo: Equatable {
    let path: String
    let version: String?
}
```

### 5.2 LibSSH2LibraryLoading

```swift
protocol LibSSH2LibraryLoading {
    func load(candidates: [String]) throws -> LoadedLibSSH2Library
}
```

`LoadedLibSSH2Library` provides:

- `info`
- `initialize() throws`
- `shutdown()`

The Darwin implementation uses:

- `dlopen`
- `dlsym`
- `dlclose`
- `libssh2_version`
- `libssh2_init`
- `libssh2_exit`

### 5.3 LibSSH2Runtime

Responsibilities:

- Own a loader.
- Own candidate paths.
- Load libssh2 lazily.
- Initialize libssh2 exactly once.
- Return `LibSSH2LibraryInfo`.
- Shut down at most once.

Non-responsibilities:

- Opening sockets.
- Authenticating SSH.
- Creating SFTP sessions.
- Reading remote directories.

### 5.4 LibSSH2RemoteFileSystem

Conforms to `RemoteFileSystem`.

For this slice:

- `connect(_:)` initializes the runtime and throws explicit unsupported-operation error.
- `disconnect(_:)` calls runtime shutdown.
- `listDirectory(_:in:)` throws `.disconnected` because real sessions do not exist yet.

Future slices will replace these stubs with real libssh2 session handles behind private implementation objects.

## 6. Error Handling

Add libssh2-specific errors:

```swift
enum LibSSH2Error: Error, Equatable {
    case libraryNotFound([String])
    case missingSymbol(String)
    case initializationFailed(Int32)
    case operationUnsupported(String)
}
```

Mapping rules:

- Library not found maps to `RemoteFileSystemError.connectionFailed`.
- Missing symbols map to `RemoteFileSystemError.connectionFailed`.
- Unsupported real SFTP operations remain explicit and testable.

## 7. Testing Requirements

Unit tests:

- Candidate paths include environment override first.
- Runtime initializes only once.
- Runtime shutdown calls loaded library shutdown once.
- Missing library returns `.libraryNotFound`.
- Adapter `connect` initializes runtime and throws explicit unsupported operation.
- Adapter `listDirectory` throws `.disconnected`.

Required real probe:

- Attempts to load candidate libssh2.
- Prints or asserts version is accessible if the library is present.
- Runs as part of the default Swift test suite.

## 8. Acceptance Criteria

- libssh2 runtime/probe types exist and are tested.
- The default test suite requires a loadable libssh2 runtime.
- `LibSSH2RemoteFileSystem` conforms to `RemoteFileSystem`.
- Adapter skeleton fails explicitly instead of silently pretending to connect.
- `swift test` passes.
- `swift build` passes.
- `docs/technical-selection.md` records that dynamic probing is the first libssh2 spike step.

## 9. Future Work

- Socket connection.
- Host-key extraction.
- Host-key verification integration.
- Password authentication.
- Public-key authentication.
- SFTP directory listing.
- Upload/download progress.
- Transfer cancellation.
- Packaging strategy for distributing libssh2 with the app.
