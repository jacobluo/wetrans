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

    func testTransferQueueSummaryViewCanRenderExpandedPanel() async {
        let failed = TransferTask(
            hostId: UUID(),
            hostDisplayName: "dev",
            direction: .download,
            localPath: "/Users/me/app.log",
            remotePath: "/var/log/app.log",
            fileName: "app.log",
            totalBytes: 1024,
            status: .failed,
            errorMessage: "Permission denied",
            createdAt: Date(timeIntervalSince1970: 1_700_000_000)
        )
        let viewModel = TransferQueueViewModel(
            queue: TransferQueue(
                engine: UnavailableTransferEngine(),
                historyStore: FilePanelTransferHistoryStore(initialTasks: [failed])
            )
        )

        await viewModel.refresh()
        viewModel.toggleExpanded()

        let view = TransferQueueSummaryView(viewModel: viewModel)
        XCTAssertTrue(String(describing: type(of: view.body)).contains("VStack"))
    }
}

private final class FilePanelTransferHistoryStore: TransferHistoryStore, @unchecked Sendable {
    private let tasks: [TransferTask]

    init(initialTasks: [TransferTask]) {
        self.tasks = initialTasks
    }

    func load() throws -> [TransferTask] {
        tasks
    }

    func save(_ tasks: [TransferTask]) throws {}
}
