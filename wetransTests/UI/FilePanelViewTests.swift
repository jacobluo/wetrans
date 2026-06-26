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
            onSelect: { _ in },
            onOpen: { _ in }
        )

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }

    func testFilePanelViewCanRenderActionButton() {
        let state = FilePanelState(
            title: "Remote",
            path: "/project",
            loadingState: .loaded([
                FileItem(name: "app.log", path: "/project/app.log", isDirectory: false)
            ]),
            selectedItemIds: ["/project/app.log"]
        )

        let view = FilePanelView(
            state: state,
            action: FilePanelAction(title: "Download", systemImage: "arrow.down.circle", isEnabled: true, perform: {}),
            onRefresh: {},
            onGoUp: {},
            onSelect: { _ in },
            onOpen: { _ in }
        )

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }

    func testMainBrowserViewCanRender() {
        let view = MainBrowserView(
            viewModel: MainBrowserViewModel(),
            onConnectHost: {}
        )

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }
}
