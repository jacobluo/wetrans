import XCTest
@testable import wetrans

final class BrowserPathTests: XCTestCase {
    func testRemoteParentKeepsRootStable() {
        XCTAssertEqual(BrowserPath.remoteParent(of: "/var/log"), "/var")
        XCTAssertEqual(BrowserPath.remoteParent(of: "/var"), "/")
        XCTAssertEqual(BrowserPath.remoteParent(of: "/"), "/")
        XCTAssertEqual(BrowserPath.remoteParent(of: "relative/path"), "relative")
    }

    func testRemoteJoinUsesPosixStylePaths() {
        XCTAssertEqual(BrowserPath.remoteJoin(directory: "/", name: "etc"), "/etc")
        XCTAssertEqual(BrowserPath.remoteJoin(directory: "/var", name: "log"), "/var/log")
        XCTAssertEqual(BrowserPath.remoteJoin(directory: "/var/", name: "log"), "/var/log")
        XCTAssertEqual(BrowserPath.remoteJoin(directory: "relative", name: "file"), "relative/file")
    }

    func testLocalParentAndJoinUseFileURLs() {
        XCTAssertEqual(BrowserPath.localParent(of: "/Users/me/Downloads"), "/Users/me")
        XCTAssertEqual(BrowserPath.localJoin(directory: "/Users/me", name: "Downloads"), "/Users/me/Downloads")
    }

    func testFilePanelStateDefaultsToIdle() {
        let state = FilePanelState(title: "Local", path: "/tmp")

        XCTAssertEqual(state.title, "Local")
        XCTAssertEqual(state.path, "/tmp")
        XCTAssertEqual(state.loadingState, .idle)
        XCTAssertEqual(state.selectedItemIds, [])
    }

    func testLoadedFilePanelStatesCompareByListingFingerprint() {
        let items = [
            FileItem(name: "a.txt", path: "/tmp/a.txt", isDirectory: false)
        ]
        let first = FilePanelState(
            title: "Local",
            path: "/tmp",
            loadingState: .loaded(items)
        )
        let second = FilePanelState(
            title: "Local",
            path: "/tmp",
            loadingState: .loaded(items)
        )

        XCTAssertEqual(first, second)
    }
}
