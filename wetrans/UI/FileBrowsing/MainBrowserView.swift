import SwiftUI

public struct MainBrowserView: View {
    @ObservedObject private var viewModel: MainBrowserViewModel
    private let onConnectHost: () -> Void

    public init(viewModel: MainBrowserViewModel, onConnectHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        NavigationSplitView {
            HostSidebarView(viewModel: viewModel.sidebarViewModel, onConnectHost: onConnectHost)
        } detail: {
            HSplitView {
                FilePanelView(
                    state: viewModel.localPanel,
                    action: FilePanelAction(
                        title: "Upload",
                        systemImage: "arrow.up.circle",
                        isEnabled: viewModel.canUploadSelection,
                        perform: {
                            Task {
                                await viewModel.enqueueUploadSelection()
                            }
                        }
                    ),
                    onRefresh: viewModel.refreshLocal,
                    onGoUp: viewModel.goUpLocal,
                    onSelect: viewModel.selectLocalItem,
                    onOpen: viewModel.openLocalItem
                )

                FilePanelView(
                    state: viewModel.remotePanel,
                    action: FilePanelAction(
                        title: "Download",
                        systemImage: "arrow.down.circle",
                        isEnabled: viewModel.canDownloadSelection,
                        perform: {
                            Task {
                                await viewModel.enqueueDownloadSelection()
                            }
                        }
                    ),
                    onRefresh: {
                        Task {
                            await viewModel.refreshRemote()
                        }
                    },
                    onGoUp: {
                        Task {
                            await viewModel.goUpRemote()
                        }
                    },
                    onSelect: viewModel.selectRemoteItem,
                    onOpen: { item in
                        Task {
                            await viewModel.openRemoteItem(item)
                        }
                    }
                )
            }
            .safeAreaInset(edge: .bottom) {
                TransferQueueSummaryView(viewModel: viewModel.transferQueueViewModel)
            }
        }
        .task {
            try? viewModel.loadHosts()
            viewModel.refreshLocal()
        }
        .onReceive(viewModel.sidebarViewModel.$selectedHostId.removeDuplicates()) { hostId in
            viewModel.select(hostId: hostId)
            viewModel.refreshLocal()
            Task {
                await viewModel.refreshRemote()
            }
        }
    }
}
