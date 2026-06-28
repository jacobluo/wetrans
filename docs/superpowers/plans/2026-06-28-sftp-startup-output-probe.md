# SFTP Startup Output Probe Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Automatically run a short SSH `true` probe after selected SFTP startup failures and show a clearer diagnostic when the remote host prints non-interactive startup output.

**Architecture:** Keep standard libssh2 SFTP as the only file transport. Add a focused probe result/diagnostic model, expose a probe method through the existing `LibSSH2Client` implementation seam, and have `LibSSH2RemoteFileSystem.connect` run the probe only when `openSFTP()` fails with a startup-like error. Preserve the original SFTP error when the probe fails or finds no output.

**Tech Stack:** Swift 6, SwiftPM, XCTest, libssh2 dynamic symbols, existing `RemoteFileSystem`, `LibSSH2Client`, and `SFTPStartupOutputDiagnostic`.

---

### File Structure

- Create: `wetrans/RemoteFileSystem/SSHStartupOutputProbe.swift`
  - Defines `SSHStartupOutputProbeResult`, output preview truncation, trigger matching, and diagnostic message formatting.
- Modify: `wetrans/RemoteFileSystem/LibSSH2Client.swift`
  - Adds `probeStartupOutput(command:timeout:outputLimit:)`.
- Modify: `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`
  - Runs a new short-lived probe client after startup-like `openSFTP()` failures.
- Modify: `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`
  - Implements the probe using libssh2 session channels and exec.
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
  - Adds adapter behavior tests and extends fakes for probe calls.
- Create: `wetransTests/RemoteFileSystem/SSHStartupOutputProbeTests.swift`
  - Adds result truncation and diagnostic formatting tests.
- Modify: `docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md`
  - Tracks task completion.

### Task 1: Probe Result And Diagnostic Model

**Files:**
- Create: `wetrans/RemoteFileSystem/SSHStartupOutputProbe.swift`
- Create: `wetransTests/RemoteFileSystem/SSHStartupOutputProbeTests.swift`
- Modify: `docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md`

- [ ] **Step 1: Write failing model tests**

Add tests that assert:

```swift
let result = SSHStartupOutputProbeResult(
    stdout: Data("Migration Tools environment loaded\n".utf8),
    stderr: Data(),
    outputLimit: 4096
)
XCTAssertEqual(result.stdoutPreview, "Migration Tools environment loaded\n")
XCTAssertFalse(result.stdoutTruncated)
XCTAssertEqual(result.evidence, .strong)
```

Also cover stderr-only weak evidence, empty no evidence, 4096 byte truncation, invalid UTF-8 replacement, startup-like trigger messages, and non-startup messages.

- [ ] **Step 2: Run focused model tests and verify they fail**

Run:

```bash
swift test --filter SSHStartupOutputProbeTests
```

Expected: FAIL because `SSHStartupOutputProbeResult` is not defined.

- [ ] **Step 3: Implement result and diagnostic model**

Create `SSHStartupOutputProbe.swift` with:

```swift
public enum SSHStartupOutputProbeEvidence: Equatable, Sendable {
    case strong
    case weak
    case none
}

public struct SSHStartupOutputProbeResult: Equatable, Sendable {
    public let stdoutPreview: String
    public let stderrPreview: String
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool

    public init(stdout: Data, stderr: Data, outputLimit: Int = 4096) {
        let stdoutPreview = Self.preview(stdout, limit: outputLimit)
        let stderrPreview = Self.preview(stderr, limit: outputLimit)
        self.stdoutPreview = stdoutPreview.text
        self.stderrPreview = stderrPreview.text
        self.stdoutTruncated = stdoutPreview.truncated
        self.stderrTruncated = stderrPreview.truncated
    }

    public var evidence: SSHStartupOutputProbeEvidence {
        if !stdoutPreview.isEmpty {
            return .strong
        }
        if !stderrPreview.isEmpty {
            return .weak
        }
        return .none
    }

    public static func shouldProbe(afterConnectionFailure message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("unable to open sftp session")
            || normalized.contains("timeout waiting for response from sftp subsystem")
            || SFTPStartupOutputDiagnostic(message: message) != nil
    }

    public func diagnosticMessage(originalError: String) -> String? {
        switch evidence {
        case .strong:
            return """
            SFTP could not start because the remote shell printed text during a non-interactive SSH session.

            Detected output:
            \(stdoutPreview)

            Move login/setup output behind an interactive-shell guard, then retry.
            Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
            """
        case .weak:
            return """
            SFTP could not start. The remote SSH startup produced diagnostics while checking for non-interactive output.

            Original SFTP error: \(originalError)

            Remote stderr:
            \(stderrPreview)

            If SFTP still fails, inspect shell startup files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
            """
        case .none:
            return nil
        }
    }

    private static func preview(_ data: Data, limit: Int) -> (text: String, truncated: Bool) {
        let boundedLimit = max(0, limit)
        let prefix = data.prefix(boundedLimit)
        return (String(decoding: prefix, as: UTF8.self), data.count > boundedLimit)
    }
}
```

- [ ] **Step 4: Run focused model tests and verify they pass**

Run:

```bash
swift test --filter SSHStartupOutputProbeTests
```

Expected: PASS.

- [ ] **Step 5: Commit model task**

Run:

```bash
git add docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md wetrans/RemoteFileSystem/SSHStartupOutputProbe.swift wetransTests/RemoteFileSystem/SSHStartupOutputProbeTests.swift
git commit -m "feat: model SSH startup output probe results"
```

### Task 2: Automatic Probe Routing In LibSSH2RemoteFileSystem

**Files:**
- Modify: `wetrans/RemoteFileSystem/LibSSH2Client.swift`
- Modify: `wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift`
- Modify: `wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift`
- Modify: `docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md`

- [ ] **Step 1: Write failing adapter tests**

Add tests asserting:

- When primary `openSFTP()` throws `RemoteFileSystemError.connectionFailed("Unable to open SFTP session")` and the probe returns stdout, `connect(_:)` throws a connection failure containing `remote shell printed text`, the stdout preview, and `~/.bashrc`.
- When the probe returns only stderr, `connect(_:)` throws a weak diagnostic containing the original SFTP error and stderr preview.
- When the probe returns no output, `connect(_:)` throws the original SFTP error.
- When the failure is `RemoteFileSystemError.connectionFailed("SSH authentication failed")`, no probe client is created.

- [ ] **Step 2: Run focused adapter test and verify it fails**

Run:

```bash
swift test --filter LibSSH2RemoteFileSystemTests/testConnectRunsStartupOutputProbeWhenSFTPOpenFailsWithStdout
```

Expected: FAIL because `LibSSH2Client` has no probe method and `LibSSH2RemoteFileSystem` does not run the probe.

- [ ] **Step 3: Add probe method to client interface and fake client**

Add to `LibSSH2Client`:

```swift
func probeStartupOutput(command: String, timeout: TimeInterval, outputLimit: Int) throws -> SSHStartupOutputProbeResult
```

Extend `FakeLibSSH2Client` with configurable `openSFTPError`, `probeResult`, `probeError`, and `probeCalls`.

- [ ] **Step 4: Route startup-like SFTP open failures through a probe client**

In `LibSSH2RemoteFileSystem.connect`, wrap `client.openSFTP()` so startup-like `RemoteFileSystemError.connectionFailed` messages call a helper that:

1. Creates a new client with `clientFactory.makeClient()`.
2. Connects, verifies the same host key decision, and authenticates.
3. Calls `probeStartupOutput(command: "true", timeout: 5, outputLimit: 4096)`.
4. Disconnects the probe client.
5. Returns `RemoteFileSystemError.connectionFailed(diagnostic)` only for strong or weak evidence.
6. Returns the original error when the probe fails or has no evidence.

- [ ] **Step 5: Run focused adapter tests and verify they pass**

Run:

```bash
swift test --filter LibSSH2RemoteFileSystemTests
```

Expected: PASS.

- [ ] **Step 6: Commit routing task**

Run:

```bash
git add docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md wetrans/RemoteFileSystem/LibSSH2Client.swift wetrans/RemoteFileSystem/LibSSH2RemoteFileSystem.swift wetransTests/RemoteFileSystem/LibSSH2RemoteFileSystemTests.swift
git commit -m "fix: probe startup output after SFTP startup failures"
```

### Task 3: libssh2 Exec Channel Probe Implementation

**Files:**
- Modify: `wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift`
- Modify: `docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md`

- [ ] **Step 1: Run typecheck and observe missing protocol implementation**

Run:

```bash
swift build
```

Expected: FAIL because `LibSSH2DynamicClient` does not yet implement `probeStartupOutput`.

- [ ] **Step 2: Implement libssh2 channel symbols and exec probe**

Add required channel symbols to `LibSSH2Symbols` and implement `LibSSH2DynamicClient.probeStartupOutput(command:timeout:outputLimit:)` by:

- Setting libssh2 session timeout to `Int(timeout * 1000)` milliseconds.
- Opening a `"session"` channel.
- Starting `"exec"` with the fixed command received from the caller.
- Reading stdout stream `0` and stderr stream `1` into capped `Data` buffers.
- Closing and freeing the channel with `defer`.
- Returning `SSHStartupOutputProbeResult(stdout:stderr:outputLimit:)`.

- [ ] **Step 3: Run typecheck**

Run:

```bash
swift build
```

Expected: PASS.

- [ ] **Step 4: Run focused probe and adapter tests**

Run:

```bash
swift test --filter SSHStartupOutputProbeTests
swift test --filter LibSSH2RemoteFileSystemTests
swift test --filter SFTPStartupOutputDiagnosticTests
```

Expected: PASS.

- [ ] **Step 5: Commit dynamic client task**

Run:

```bash
git add docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md wetrans/RemoteFileSystem/LibSSH2DynamicClient.swift
git commit -m "feat: add libssh2 startup output exec probe"
```

### Task 4: Final Verification

**Files:**
- Modify: `docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md`

- [ ] **Step 1: Run full verification**

Run:

```bash
scripts/verify
```

Expected: PASS. If the packaged app smoke is blocked by local macOS Accessibility permissions, record the exact blocker and run the remaining focused commands.

- [ ] **Step 2: Commit final plan checkbox update**

Run:

```bash
git add docs/superpowers/plans/2026-06-28-sftp-startup-output-probe.md
git commit -m "docs: complete startup output probe plan"
```
