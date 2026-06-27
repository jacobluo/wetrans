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

    func testBuildsSuspectedStartupOutputMessageForSFTPSubsystemTimeout() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Timeout waiting for response from SFTP subsystem")

        XCTAssertEqual(diagnostic?.detectedOutputPrefix, nil)
        XCTAssertTrue(diagnostic?.userMessage.contains("SFTP did not respond during startup or directory browsing") == true)
        XCTAssertTrue(diagnostic?.userMessage.contains("ssh <host> true") == true)
        XCTAssertTrue(diagnostic?.userMessage.contains("Timeout waiting for response from SFTP subsystem") == true)
    }

    func testBuildsSuspectedStartupOutputMessageForFXPOpenFailure() {
        let diagnostic = SFTPStartupOutputDiagnostic(message: "Unable to send FXP_OPEN*")

        XCTAssertEqual(diagnostic?.detectedOutputPrefix, nil)
        XCTAssertTrue(diagnostic?.userMessage.contains("SFTP did not respond during startup or directory browsing") == true)
        XCTAssertTrue(diagnostic?.userMessage.contains("Unable to send FXP_OPEN*") == true)
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
