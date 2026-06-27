# Logs, Debug Detail, and Checklist Lite Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Add the first safe diagnostic surface for internal testing: redacted copyable debug details, lightweight app logs, and an internal tester checklist.

**Architecture:** Keep diagnostics behind small support types so UI code does not know redaction or OSLog details. `MainBrowserViewModel` owns browser event context and receives injectable `DiagnosticLogging` plus existing `PasteboardWriting`; `FilePanelView` only renders a failed-state copy action when provided.

**Tech Stack:** Swift, SwiftUI, OSLog, XCTest, existing `PasteboardWriting`.

---

## Task 1: Diagnostic Formatting

**Files:**
- Create: `wetrans/Support/DiagnosticDetail.swift`
- Test: `wetransTests/Support/DiagnosticDetailTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for report formatting and redaction:

```swift
import XCTest
@testable import wetrans

final class DiagnosticDetailTests: XCTestCase {
    func testReportIncludesPanelPathMessageAndHost() {
        let detail = DiagnosticDetail(
            panel: "Remote",
            path: "/srv/project",
            message: "Permission denied: /srv/project",
            hostDisplayName: "Example Host"
        )

        XCTAssertEqual(
            detail.report,
            """
            wetrans debug detail
            panel: Remote
            path: /srv/project
            message: Permission denied: /srv/project
            host: Example Host
            """
        )
    }

    func testReportOmitsHostWhenUnavailable() {
        let detail = DiagnosticDetail(
            panel: "Local",
            path: "/tmp",
            message: "Cannot read local directory: /tmp",
            hostDisplayName: nil
        )

        XCTAssertFalse(detail.report.contains("host:"))
    }

    func testReportRedactsHomePathsAndSecretWords() {
        let detail = DiagnosticDetail(
            panel: "Remote",
            path: "/Users/alice/.ssh/id_ed25519",
            message: "password hunter2 passphrase open-sesame at /Users/alice/project",
            hostDisplayName: "Prod"
        )

        XCTAssertFalse(detail.report.contains("alice"))
        XCTAssertFalse(detail.report.contains("hunter2"))
        XCTAssertFalse(detail.report.contains("open-sesame"))
        XCTAssertTrue(detail.report.contains("/Users/<user>"))
        XCTAssertTrue(detail.report.contains("password <redacted>"))
        XCTAssertTrue(detail.report.contains("passphrase <redacted>"))
    }
}
```

- [x] **Step 2: Verify red**

Run: `swift test --filter DiagnosticDetailTests`

Expected: FAIL because `DiagnosticDetail` does not exist.

- [x] **Step 3: Implement minimal formatter**

Create `DiagnosticDetail` with deterministic report lines and conservative redaction.

- [x] **Step 4: Verify green**

Run: `swift test --filter DiagnosticDetailTests`

Expected: PASS.

## Task 2: Logger Boundary

**Files:**
- Create: `wetrans/Support/DiagnosticLogging.swift`
- Test: `wetransTests/Support/DiagnosticLoggingTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for in-memory capture and redacted values:

```swift
import XCTest
@testable import wetrans

final class DiagnosticLoggingTests: XCTestCase {
    func testRecordingLoggerCapturesRedactedMetadata() {
        let logger = RecordingDiagnosticLogger()

        logger.log(
            .remoteRefreshFailed,
            message: "password secret",
            metadata: ["path": "/Users/alice/project"]
        )

        XCTAssertEqual(logger.entries.count, 1)
        XCTAssertEqual(logger.entries[0].event, .remoteRefreshFailed)
        XCTAssertEqual(logger.entries[0].message, "password <redacted>")
        XCTAssertEqual(logger.entries[0].metadata["path"], "/Users/<user>/project")
    }
}
```

- [x] **Step 2: Verify red**

Run: `swift test --filter DiagnosticLoggingTests`

Expected: FAIL because `DiagnosticLogging` and `RecordingDiagnosticLogger` do not exist.

- [x] **Step 3: Implement logger protocol and sinks**

Add:

- `DiagnosticLogEvent`
- `DiagnosticLogEntry`
- `DiagnosticLogging`
- `OSLogDiagnosticLogger`
- `RecordingDiagnosticLogger`

- [x] **Step 4: Verify green**

Run: `swift test --filter DiagnosticLoggingTests`

Expected: PASS.

## Task 3: Browser View Model Hooks

**Files:**
- Modify: `wetrans/UI/FileBrowsing/MainBrowserViewModel.swift`
- Test: `wetransTests/UI/MainBrowserViewModelTests.swift`

- [x] **Step 1: Write failing tests**

Add tests for copying failed panel debug details and logging:

```swift
func testCopyRemoteDebugDetailWritesRedactedFailureToPasteboard() async {
    let pasteboard = RecordingPasteboardWriter()
    let viewModel = makeViewModel(
        hosts: [makeHost(displayName: "Prod")],
        remoteFileSystem: MockRemoteFileSystem(
            listErrorsByPath: ["/Users/alice/project": RemoteFileSystemError.permissionDenied("/Users/alice/project")]
        ),
        pasteboardWriter: pasteboard
    )

    viewModel.select(hostId: viewModel.hosts[0].id)
    await viewModel.enterRemotePath("/Users/alice/project")
    viewModel.copyRemoteDebugDetail()

    XCTAssertTrue(pasteboard.lastString?.contains("panel: Remote") == true)
    XCTAssertTrue(pasteboard.lastString?.contains("host: Prod") == true)
    XCTAssertFalse(pasteboard.lastString?.contains("alice") == true)
}

func testRemoteRefreshFailureLogsDiagnosticEvent() async {
    let logger = RecordingDiagnosticLogger()
    let viewModel = makeViewModel(
        hosts: [makeHost()],
        remoteFileSystem: MockRemoteFileSystem(
            listErrorsByPath: ["/project": RemoteFileSystemError.permissionDenied("/project")]
        ),
        logger: logger
    )

    viewModel.select(hostId: viewModel.hosts[0].id)
    await viewModel.refreshRemote()

    XCTAssertTrue(logger.entries.contains { $0.event == .remoteRefreshFailed })
}
```

- [x] **Step 2: Verify red**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: FAIL because the view model lacks diagnostic copy methods and logger injection.

- [x] **Step 3: Implement hooks**

Inject `DiagnosticLogging`, add `copyLocalDebugDetail()` and `copyRemoteDebugDetail()`, log local/remote refresh failures, transfer enqueue counts, and observed transfer completion events.

- [x] **Step 4: Verify green**

Run: `swift test --filter MainBrowserViewModelTests`

Expected: PASS.

## Task 4: Failed-State Copy UI

**Files:**
- Modify: `wetrans/UI/FileBrowsing/FilePanelView.swift`
- Modify: `wetrans/UI/FileBrowsing/MainBrowserView.swift`
- Test: `wetransTests/UI/FilePanelViewTests.swift`

- [x] **Step 1: Write failing compile/render smoke**

Add a test that constructs `FilePanelView` with `onCopyDebugDetail`.

- [x] **Step 2: Verify red**

Run: `swift test --filter FilePanelViewTests`

Expected: FAIL because `FilePanelView` does not accept the copy action.

- [x] **Step 3: Add copy button to failed state**

Add an optional `onCopyDebugDetail` closure to `FilePanelView`. Render a compact `Copy Debug Detail` button only for `.failed`.

- [x] **Step 4: Wire browser view**

Pass `viewModel.copyLocalDebugDetail` and `viewModel.copyRemoteDebugDetail` from `MainBrowserView`.

- [x] **Step 5: Verify green**

Run: `swift test --filter FilePanelViewTests`

Expected: PASS.

## Task 5: Internal Tester Checklist

**Files:**
- Create: `docs/internal-test-checklist.md`

- [x] **Step 1: Add checklist**

Document the default tester flow: package app, launch, add manual host, add SSH Config host, browse local and remote directories, upload/download single files, inspect queue, retry/cancel, collect debug detail, and note what to include in bug reports.

- [x] **Step 2: Verify doc references**

Run: `rg -n "Copy Debug Detail|internal tester|debug detail" docs`

Expected: Checklist and diagnostics docs are discoverable.

## Task 6: Final Verification

- [x] **Step 1: Run focused tests**

Run:

```bash
swift test --filter DiagnosticDetailTests
swift test --filter DiagnosticLoggingTests
swift test --filter MainBrowserViewModelTests
swift test --filter FilePanelViewTests
```

Expected: PASS.

- [x] **Step 2: Run full verification**

Run: `scripts/verify`

Expected: PASS.

- [x] **Step 3: Commit**

Run:

```bash
git add docs/superpowers/specs/logs-debug-detail-checklist-lite-spec.md docs/superpowers/plans/logs-debug-detail-checklist-lite-plan.md docs/internal-test-checklist.md wetrans/Support/DiagnosticDetail.swift wetrans/Support/DiagnosticLogging.swift wetrans/UI/FileBrowsing/MainBrowserViewModel.swift wetrans/UI/FileBrowsing/FilePanelView.swift wetrans/UI/FileBrowsing/MainBrowserView.swift wetransTests/Support/DiagnosticDetailTests.swift wetransTests/Support/DiagnosticLoggingTests.swift wetransTests/UI/MainBrowserViewModelTests.swift wetransTests/UI/FilePanelViewTests.swift
git commit -m "feat: add lite diagnostics"
```
