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
                    contextActions: { item in
                        [
                            FilePanelContextAction(
                                id: "upload-\(item.id)",
                                title: "Upload",
                                systemImage: "arrow.up.circle",
                                isEnabled: viewModel.selectedHost != nil && !item.isDirectory,
                                perform: {
                                    Task {
                                        await viewModel.enqueueUpload(item)
                                    }
                                }
                            ),
                            FilePanelContextAction(
                                id: "reveal-\(item.id)",
                                title: "Show in Finder",
                                systemImage: "magnifyingglass",
                                isEnabled: true,
                                perform: {
                                    viewModel.revealLocalItemInFinder(item)
                                }
                            ),
                            FilePanelContextAction(
                                id: "refresh-local-\(item.id)",
                                title: "Refresh",
                                systemImage: "arrow.clockwise",
                                isEnabled: true,
                                perform: viewModel.refreshLocal
                            )
                        ]
                    },
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
                    contextActions: { item in
                        [
                            FilePanelContextAction(
                                id: "download-\(item.id)",
                                title: "Download",
                                systemImage: "arrow.down.circle",
                                isEnabled: viewModel.selectedHost != nil && !item.isDirectory,
                                perform: {
                                    Task {
                                        await viewModel.enqueueDownload(item)
                                    }
                                }
                            ),
                            FilePanelContextAction(
                                id: "copy-path-\(item.id)",
                                title: "Copy Remote Path",
                                systemImage: "doc.on.doc",
                                isEnabled: true,
                                perform: {
                                    viewModel.copyRemotePath(item)
                                }
                            ),
                            FilePanelContextAction(
                                id: "refresh-remote-\(item.id)",
                                title: "Refresh",
                                systemImage: "arrow.clockwise",
                                isEnabled: true,
                                perform: {
                                    Task {
                                        await viewModel.refreshRemote()
                                    }
                                }
                            )
                        ]
                    },
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
        .onReceive(viewModel.sidebarViewModel.$selectedHostId.dropFirst().removeDuplicates()) { hostId in
            viewModel.select(hostId: hostId)
            viewModel.refreshLocal()
            Task {
                await viewModel.refreshRemote()
            }
        }
    }
}
