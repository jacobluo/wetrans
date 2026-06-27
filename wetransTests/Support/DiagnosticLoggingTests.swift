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
