import SwiftUI

public struct MainBrowserView: View {
    @ObservedObject private var viewModel: MainBrowserViewModel
    private let onConnectHost: () -> Void

    public init(viewModel: MainBrowserViewModel, onConnectHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        VStack(spacing: 0) {
            WetransTopBar(onConnectHost: onConnectHost)

            HStack(spacing: 0) {
                HostSidebarView(viewModel: viewModel.sidebarViewModel, onConnectHost: onConnectHost)
                    .frame(width: 236)

                VStack(spacing: 8) {
                    HSplitView {
                        localPanel
                        remotePanel
                    }
                    .frame(minHeight: 360)

                    TransferQueueSummaryView(viewModel: viewModel.transferQueueViewModel)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
                        }
                }
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .accessibilityIdentifier("Wetrans Main Browser")
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
        .alert(
            "Confirm Host Key",
            isPresented: Binding(
                get: { viewModel.pendingHostKeyTrust != nil },
                set: { _ in }
            )
        ) {
            Button("Trust and Continue") {
                Task {
                    await viewModel.trustPendingHostKeyAndRefresh()
                }
            }
            .accessibilityIdentifier("Host Key Trust Continue")
            Button("Cancel", role: .cancel) {
                viewModel.cancelPendingHostKeyTrust()
            }
            .accessibilityIdentifier("Host Key Trust Cancel")
        } message: {
            Text(viewModel.pendingHostKeyTrustMessage)
        }
    }

    private var localPanel: some View {
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
    }

    private var remotePanel: some View {
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
}

private struct WetransTopBar: View {
    let onConnectHost: () -> Void

    var body: some View {
        HStack(spacing: 14) {
            Text("wetrans")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)

            Spacer()

            Button(action: onConnectHost) {
                Text("Connect Host")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .accessibilityIdentifier("Connect Host Toolbar")

            Button {} label: {
                Image(systemName: "ellipsis")
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .help("More")
        }
        .padding(.horizontal, 18)
        .frame(height: 52)
        .background(.bar)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}
