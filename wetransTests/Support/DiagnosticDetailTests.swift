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
            message: "password hunter2 passphrase open-sesame token abc123 authorization Bearer-secret at /Users/alice/project",
            hostDisplayName: "Prod"
        )

        XCTAssertFalse(detail.report.contains("alice"))
        XCTAssertFalse(detail.report.contains("hunter2"))
        XCTAssertFalse(detail.report.contains("open-sesame"))
        XCTAssertFalse(detail.report.contains("abc123"))
        XCTAssertFalse(detail.report.contains("Bearer-secret"))
        XCTAssertTrue(detail.report.contains("/Users/<user>"))
        XCTAssertTrue(detail.report.contains("password <redacted>"))
        XCTAssertTrue(detail.report.contains("passphrase <redacted>"))
        XCTAssertTrue(detail.report.contains("token <redacted>"))
        XCTAssertTrue(detail.report.contains("authorization <redacted>"))
    }
}
