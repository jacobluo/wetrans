import SwiftUI
import XCTest
@testable import wetrans

@MainActor
final class FilePanelViewTests: XCTestCase {
    func testFilePanelRowsUseImmediateSelectionControl() {
        XCTAssertTrue(FilePanelInteractionPolicy.usesImmediateSelectionControl)
    }

    func testFilePanelToolbarUsesCompactIconButtonsInDesignOrder() {
        XCTAssertEqual(FilePanelLayout.toolbarButtonSide, 24)
        XCTAssertEqual(FilePanelLayout.toolbarButtonCornerRadius, 5)
        XCTAssertFalse(FilePanelLayout.transferActionShowsTitle)
        XCTAssertEqual(FilePanelLayout.toolbarOrder, [.goUp, .refresh, .transfer])
        XCTAssertEqual(FilePanelLayout.systemImage(for: .goUp, transferSystemImage: "arrow.down.to.line"), "arrow.up")
        XCTAssertEqual(FilePanelLayout.systemImage(for: .refresh, transferSystemImage: "arrow.down.to.line"), "arrow.clockwise")
        XCTAssertEqual(FilePanelLayout.systemImage(for: .transfer, transferSystemImage: "arrow.down.to.line"), "arrow.down.to.line")
        XCTAssertEqual(FilePanelLayout.helpText(for: .goUp, transferTitle: "Download"), "Go to Parent Directory")
        XCTAssertEqual(FilePanelLayout.helpText(for: .refresh, transferTitle: "Download"), "Refresh")
        XCTAssertEqual(FilePanelLayout.helpText(for: .transfer, transferTitle: "Download"), "Download")
    }

    func testFilePanelListSupportsHorizontalScrollingForWideRows() {
        XCTAssertGreaterThanOrEqual(FilePanelLayout.tableContentMinWidth, 640)
        XCTAssertTrue(FilePanelLayout.usesSeparateHorizontalAndVerticalScrolling)
    }

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
            onSelect: { _, _ in },
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
            onSelect: { _, _ in },
            onOpen: { _ in }
        )

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }

    func testFilePanelViewCanRenderContextActions() {
        let state = FilePanelState(
            title: "Local",
            path: "/tmp",
            loadingState: .loaded([
                FileItem(name: "config.yaml", path: "/tmp/config.yaml", isDirectory: false)
            ])
        )

        let view = FilePanelView(
            state: state,
            contextActions: { item in
                [
                    FilePanelContextAction(
                        id: "upload-\(item.id)",
                        title: "Upload",
                        systemImage: "arrow.up.circle",
                        isEnabled: true,
                        perform: {}
                    )
                ]
            },
            onRefresh: {},
            onGoUp: {},
            onSelect: { _, _ in },
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

    func testConnectHostDialogViewCanRenderDesignOptions() {
        let view = ConnectHostDialogView()

        XCTAssertNotNil(String(describing: type(of: view.body)))
    }

    func testConnectHostSheetViewCanRenderActionBackedFlow() {
        let view = ConnectHostSheetView(
            catalog: FilePanelHostCatalog(),
            credentialStore: FilePanelCredentialStore(),
            onSaved: { _ in }
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

    func testTransferQueueLayoutCanBeVerticallyResized() {
        XCTAssertTrue(TransferQueueLayout.isVerticallyResizable)
        XCTAssertGreaterThanOrEqual(TransferQueueLayout.expandedMinHeight, 150)
        XCTAssertGreaterThanOrEqual(TransferQueueLayout.expandedIdealHeight, TransferQueueLayout.expandedMinHeight)
        XCTAssertGreaterThanOrEqual(
            MainBrowserLayout.queueHeight(for: 1_000, requestedQueueHeight: 520),
            500
        )
        XCTAssertEqual(MainBrowserLayout.sectionSpacing, 8)
        XCTAssertEqual(MainBrowserLayout.resizeHandleHeight, 8)
        XCTAssertLessThanOrEqual(
            MainBrowserLayout.verticalGapBetweenFilePanelsAndQueue,
            MainBrowserLayout.sectionSpacing + MainBrowserLayout.resizeHandleHeight
        )
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

private final class FilePanelHostCatalog: HostCatalog {
    func load() throws -> [SavedHost] { [] }
    func save(_ host: SavedHost) throws {}
    func delete(hostId: UUID) throws {}
    func markConnected(hostId: UUID, at date: Date) throws {}
    func updatePaths(hostId: UUID, local: String?, remote: String?) throws {}
    func setFavorite(hostId: UUID, isFavorite: Bool) throws {}
}

private final class FilePanelCredentialStore: CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws {}
    func loadPassword(hostId: UUID) throws -> String? { nil }
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws {}
    func loadKeyPassphrase(hostId: UUID) throws -> String? { nil }
    func deleteCredentials(hostId: UUID) throws {}
}
