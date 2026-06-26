import XCTest
@testable import wetrans

final class LibSSH2DynamicClientTests: XCTestCase {
    func testJoinBuildsRemoteChildPaths() {
        XCTAssertEqual(LibSSH2Path.join(directory: "/var/log", name: "app.log"), "/var/log/app.log")
        XCTAssertEqual(LibSSH2Path.join(directory: "/", name: "etc"), "/etc")
        XCTAssertEqual(LibSSH2Path.join(directory: "relative", name: "file"), "relative/file")
    }

    func testPermissionsTextUsesUnixStyleFileTypeAndModeBits() {
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o040755), "drwxr-xr-x")
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o100644), "-rw-r--r--")
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o120777), "lrwxrwxrwx")
    }

    func testFileTypeHelpersUseModeBits() {
        XCTAssertTrue(LibSSH2Path.isDirectory(permissions: 0o040755))
        XCTAssertFalse(LibSSH2Path.isDirectory(permissions: 0o100644))
        XCTAssertTrue(LibSSH2Path.isSymlink(permissions: 0o120777))
        XCTAssertFalse(LibSSH2Path.isSymlink(permissions: 0o100644))
    }
}
