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
                    onRefresh: viewModel.refreshLocal,
                    onGoUp: viewModel.goUpLocal,
                    onOpen: viewModel.openLocalItem
                )

                FilePanelView(
                    state: viewModel.remotePanel,
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
