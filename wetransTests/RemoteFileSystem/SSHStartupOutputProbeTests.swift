import Foundation
import XCTest
@testable import wetrans

final class SSHStartupOutputProbeTests: XCTestCase {
    func testStdoutProducesStrongEvidence() {
        let result = SSHStartupOutputProbeResult(
            stdout: Data("Migration Tools environment loaded\n".utf8),
            stderr: Data(),
            outputLimit: 4096
        )

        XCTAssertEqual(result.stdoutPreview, "Migration Tools environment loaded\n")
        XCTAssertEqual(result.stderrPreview, "")
        XCTAssertFalse(result.stdoutTruncated)
        XCTAssertFalse(result.stderrTruncated)
        XCTAssertEqual(result.evidence, .strong)
    }

    func testStderrOnlyProducesWeakEvidence() {
        let result = SSHStartupOutputProbeResult(
            stdout: Data(),
            stderr: Data("bash: warning: setlocale\n".utf8),
            outputLimit: 4096
        )

        XCTAssertEqual(result.stdoutPreview, "")
        XCTAssertEqual(result.stderrPreview, "bash: warning: setlocale\n")
        XCTAssertEqual(result.evidence, .weak)
    }

    func testNoOutputProducesNoEvidence() {
        let result = SSHStartupOutputProbeResult(stdout: Data(), stderr: Data(), outputLimit: 4096)

        XCTAssertEqual(result.evidence, .none)
        XCTAssertNil(result.diagnosticMessage(originalError: "Unable to open SFTP session"))
    }

    func testOutputPreviewIsCappedAndMarkedTruncated() {
        let data = Data(String(repeating: "a", count: 4097).utf8)

        let result = SSHStartupOutputProbeResult(stdout: data, stderr: data, outputLimit: 4096)

        XCTAssertEqual(result.stdoutPreview.count, 4096)
        XCTAssertEqual(result.stderrPreview.count, 4096)
        XCTAssertTrue(result.stdoutTruncated)
        XCTAssertTrue(result.stderrTruncated)
    }

    func testInvalidUTF8IsRenderedSafely() {
        let result = SSHStartupOutputProbeResult(stdout: Data([0xff, 0xfe, 0x41]), stderr: Data(), outputLimit: 4096)

        XCTAssertEqual(result.stdoutPreview, "\u{fffd}\u{fffd}A")
        XCTAssertEqual(result.evidence, .strong)
    }

    func testStrongDiagnosticMessageIncludesOutputAndRemediation() {
        let result = SSHStartupOutputProbeResult(
            stdout: Data("Migration Tools environment loaded\n".utf8),
            stderr: Data(),
            outputLimit: 4096
        )

        let message = result.diagnosticMessage(originalError: "Unable to open SFTP session")

        XCTAssertTrue(message?.contains("remote shell printed text") == true)
        XCTAssertTrue(message?.contains("Migration Tools environment loaded") == true)
        XCTAssertTrue(message?.contains("~/.bashrc") == true)
        XCTAssertFalse(message?.contains("Unable to open SFTP session") == true)
    }

    func testWeakDiagnosticMessageIncludesOriginalErrorAndStderr() {
        let result = SSHStartupOutputProbeResult(
            stdout: Data(),
            stderr: Data("bash: warning: setlocale\n".utf8),
            outputLimit: 4096
        )

        let message = result.diagnosticMessage(originalError: "Unable to open SFTP session")

        XCTAssertTrue(message?.contains("Unable to open SFTP session") == true)
        XCTAssertTrue(message?.contains("bash: warning: setlocale") == true)
        XCTAssertTrue(message?.contains("startup files") == true)
    }

    func testStartupLikeConnectionFailureMessagesTriggerProbe() {
        XCTAssertTrue(SSHStartupOutputProbeResult.shouldProbe(afterConnectionFailure: "Unable to open SFTP session"))
        XCTAssertTrue(
            SSHStartupOutputProbeResult.shouldProbe(
                afterConnectionFailure: "Timeout waiting for response from SFTP subsystem"
            )
        )
        XCTAssertTrue(
            SSHStartupOutputProbeResult.shouldProbe(afterConnectionFailure: "Received message too long 1298753394")
        )
    }

    func testNonStartupConnectionFailuresDoNotTriggerProbe() {
        XCTAssertFalse(SSHStartupOutputProbeResult.shouldProbe(afterConnectionFailure: "SSH authentication failed"))
        XCTAssertFalse(SSHStartupOutputProbeResult.shouldProbe(afterConnectionFailure: "Unable to send FXP_OPEN*"))
        XCTAssertFalse(SSHStartupOutputProbeResult.shouldProbe(afterConnectionFailure: "nodename nor servname provided"))
    }
}
