# SFTP Startup Output Diagnostics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Show a specific, actionable diagnostic when an SFTP failure message contains packet-length evidence that the remote shell printed startup text before the SFTP protocol began.

**Architecture:** Add a small `SFTPStartupOutputDiagnostic` value type under the RemoteFileSystem boundary to parse connection failure strings and expose a user-facing remediation message. Keep transport behavior unchanged and route only matching `RemoteFileSystemError.connectionFailed` messages through the diagnostic helper in `MainBrowserViewModel`.

**Tech Stack:** Swift 6, SwiftPM, XCTest, existing `RemoteFileSystemError` and `MainBrowserViewModel` error mapping.

---

### Task 1: Diagnostic Helper And Unit Tests

**Files:**
- Create: `wetrans/RemoteFileSystem/SFTPStartupOutputDiagnostic.swift`
- Create: `wetransTests/RemoteFileSystem/SFTPStartupOutputDiagnosticTests.swift`

- [x] **Step 1: Write the failing helper tests**

Add `wetransTests/RemoteFileSystem/SFTPStartupOutputDiagnosticTests.swift`:

```swift
import XCTest
@testable import wetrans

final class SFTPStartupOutputDiagnosticTests: XCTestCase {
    func testDecodesPacketLengthPrefixWhenBytesArePrintableASCII() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Received message too long 1298753394")

        XCTAssertEqual(diagnostic?.detectedOutputPrefix, "Migr")
    }

    func testBuildsActionableMessageForStartupOutputPollution() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Received message too long 1298753394")

        XCTAssertEqual(
            diagnostic?.userMessage,
            """
            SFTP could not start because the remote shell printed text before the SFTP protocol began.

            Detected output prefix: "Migr"

            Move login/setup echo output behind an interactive-shell guard, then retry.
            Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
            """
        )
    }

    func testIgnoresPacketLengthWhenDecodedBytesAreNotPrintableASCII() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Received message too long 1")

        XCTAssertNil(diagnostic)
    }

    func testIgnoresUnrelatedConnectionFailureMessage() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Unable to open SFTP session")

        XCTAssertNil(diagnostic)
    }
}
```

- [x] **Step 2: Run focused helper tests and verify they fail**

Run: `swift test --filter SFTPStartupOutputDiagnosticTests`

Expected: FAIL because `SFTPStartupOutputDiagnostic` is not defined.

- [x] **Step 3: Implement the minimal diagnostic helper**

Create `wetrans/RemoteFileSystem/SFTPStartupOutputDiagnostic.swift`:

```swift
import Foundation

public struct SFTPStartupOutputDiagnostic: Equatable, Sendable {
    public let detectedOutputPrefix: String

    public init?(message: String) {
        guard let length = Self.packetLengthValue(in: message),
              let prefix = Self.printablePrefix(from: length)
        else {
            return nil
        }
        self.detectedOutputPrefix = prefix
    }

    public var userMessage: String {
        """
        SFTP could not start because the remote shell printed text before the SFTP protocol began.

        Detected output prefix: "\(detectedOutputPrefix)"

        Move login/setup echo output behind an interactive-shell guard, then retry.
        Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
        """
    }

    private static func packetLengthValue(in message: String) -> UInt32? {
        guard message.localizedCaseInsensitiveContains("received message too long") else {
            return nil
        }
        let scanner = Scanner(string: message)
        while !scanner.isAtEnd {
            var value: UInt64 = 0
            if scanner.scanUnsignedLongLong(&value), value <= UInt32.max {
                return UInt32(value)
            }
            _ = scanner.scanUpToCharacters(from: .decimalDigits)
        }
        return nil
    }

    private static func printablePrefix(from length: UInt32) -> String? {
        let bytes = [
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ]
        guard bytes.allSatisfy({ 0x20...0x7e ~= $0 }) else {
            return nil
        }
        return String(bytes: bytes, encoding: .ascii)
    }
}
```

- [x] **Step 4: Run focused helper tests and verify they pass**

Run: `swift test --filter SFTPStartupOutputDiagnosticTests`

Expected: PASS.

- [x] **Step 5: Commit helper task**

Run:

```bash
git add docs/superpowers/plans/sftp-startup-output-diagnostics-plan.md wetrans/RemoteFileSystem/SFTPStartupOutputDiagnostic.swift wetransTests/RemoteFileSystem/SFTPStartupOutputDiagnosticTests.swift
git commit -m "feat: diagnose SFTP startup output prefixes"
```

### Task 2: Remote Error Message Routing

**Files:**
- Modify: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Modify: `wetransTests/UI/MainBrowserViewModelTests.swift`
- Modify: `docs/superpowers/plans/sftp-startup-output-diagnostics-plan.md`

- [ ] **Step 1: Write failing ViewModel routing tests**

Add these tests near existing remote error tests in `wetransTests/UI/MainBrowserViewModelTests.swift`:

```swift
func testRemoteStartupOutputConnectionFailureShowsSpecificDiagnostic() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let remoteFileSystem = MockRemoteFileSystem(
        listErrorsByPath: [
            "/project": RemoteFileSystemError.connectionFailed("Received message too long 1298753394")
        ]
    )
    let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.refreshRemote()

    XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("remote shell printed text"))
    XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("Detected output prefix: \"Migr\""))
    XCTAssertTrue(viewModel.remotePanel.errorMessage.contains("~/.bashrc"))
    XCTAssertFalse(viewModel.remotePanel.errorMessage.contains("Received message too long 1298753394"))
}

func testUnrelatedRemoteConnectionFailureMessageIsUnchanged() async throws {
    let host = SavedHost.fixture(lastRemotePath: "/project", lastLocalPath: "/Users/me/Downloads")
    let remoteFileSystem = MockRemoteFileSystem(
        listErrorsByPath: [
            "/project": RemoteFileSystemError.connectionFailed("Unable to open SFTP session")
        ]
    )
    let viewModel = makeViewModel(hosts: [host], remoteFileSystem: remoteFileSystem)

    try viewModel.loadHosts()
    viewModel.select(hostId: host.id)
    await viewModel.refreshRemote()

    XCTAssertEqual(viewModel.remotePanel.errorMessage, "Unable to open SFTP session")
}
```

- [ ] **Step 2: Run focused ViewModel tests and verify the new routing test fails**

Run: `swift test --filter MainBrowserViewModelTests/testRemoteStartupOutputConnectionFailureShowsSpecificDiagnostic`

Expected: FAIL because `MainBrowserViewModel` still returns the raw connection failure message.

- [ ] **Step 3: Route matching connection failures through the diagnostic helper**

Change the `RemoteFileSystemError.connectionFailed` branch in `MainBrowserViewModel.message(forRemoteError:)` to:

```swift
case RemoteFileSystemError.connectionFailed(let message):
    if let diagnostic = SFTPStartupOutputDiagnostic(message: message) {
        return diagnostic.userMessage
    }
    return message
```

- [ ] **Step 4: Run focused ViewModel tests and verify they pass**

Run: `swift test --filter MainBrowserViewModelTests/testRemoteStartupOutputConnectionFailureShowsSpecificDiagnostic && swift test --filter MainBrowserViewModelTests/testUnrelatedRemoteConnectionFailureMessageIsUnchanged`

Expected: PASS.

- [ ] **Step 5: Run broader verification**

Run: `scripts/verify`

Expected: PASS.

- [ ] **Step 6: Commit routing task**

Run:

```bash
git add docs/superpowers/plans/sftp-startup-output-diagnostics-plan.md wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetransTests/UI/MainBrowserViewModelTests.swift
git commit -m "fix: show SFTP startup output diagnostics"
```
