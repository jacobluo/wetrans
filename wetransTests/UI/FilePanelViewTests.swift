import SwiftUI
import XCTest
@testable import wetrans

@MainActor
final class FilePanelViewTests: XCTestCase {
    func testFilePanelViewCanRenderLoadedState() {
        let state = FilePanelState(
            title: "Local",
            path: "/tmp",
            loadingState: .loaded([
                FileItem(name: "folder", path: "/tmp/folder", isDirectory: true)
            ])
        )

        let view = FilePanelView(
            state: state,
            onRefresh: {},
            onGoUp: {},
            onOpen: { _ in }
        )

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }
}
