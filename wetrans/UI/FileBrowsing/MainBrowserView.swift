import SwiftUI

public enum MainBrowserLayout {
    public static let sectionSpacing: CGFloat = 8
    public static let resizeHandleHeight: CGFloat = 8
    public static let minimumFilePanelsHeight: CGFloat = 300
    public static let verticalGapBetweenFilePanelsAndQueue: CGFloat = resizeHandleHeight

    public static func queueHeight(for availableHeight: CGFloat, requestedQueueHeight: CGFloat) -> CGFloat {
        let maxQueueHeight = max(
            TransferQueueLayout.expandedMinHeight,
            availableHeight - minimumFilePanelsHeight - resizeHandleHeight
        )
        return min(max(requestedQueueHeight, TransferQueueLayout.expandedMinHeight), maxQueueHeight)
    }
}

public struct MainBrowserView: View {
    @ObservedObject private var viewModel: MainBrowserViewModel
    private let onConnectHost: () -> Void
    @State private var transferQueueHeight = TransferQueueLayout.expandedIdealHeight
    @State private var transferQueueHeightAtDragStart: CGFloat?

    public init(viewModel: MainBrowserViewModel, onConnectHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        HStack(spacing: 0) {
            HostSidebarView(viewModel: viewModel.sidebarViewModel, onConnectHost: onConnectHost)
                .frame(width: 236)

            workbench
                .padding(10)
                .background(Color(nsColor: .windowBackgroundColor))
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .task {
            try? viewModel.loadHosts()
            viewModel.refreshLocal()
        }
        .task {
            await runIdleSessionCleanupLoop()
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

    @ViewBuilder
    private var workbench: some View {
        if viewModel.transferQueueViewModel.isExpanded {
            GeometryReader { proxy in
                expandedWorkbench(availableHeight: proxy.size.height)
            }
        } else {
            VStack(spacing: MainBrowserLayout.sectionSpacing) {
                filePanels
                    .frame(minHeight: 360)

                transferQueue
            }
        }
    }

    private func expandedWorkbench(availableHeight: CGFloat) -> some View {
        let queueHeight = MainBrowserLayout.queueHeight(
            for: availableHeight,
            requestedQueueHeight: transferQueueHeight
        )
        let filePanelsHeight = max(
            MainBrowserLayout.minimumFilePanelsHeight,
            availableHeight - queueHeight - MainBrowserLayout.resizeHandleHeight
        )

        return VStack(spacing: 0) {
            filePanels
                .frame(height: filePanelsHeight)

            resizeHandle(availableHeight: availableHeight)

            transferQueue
                .frame(height: queueHeight)
        }
    }

    private var filePanels: some View {
        HSplitView {
            localPanel
            remotePanel
        }
        .frame(maxHeight: .infinity)
    }

    private var transferQueue: some View {
        TransferQueueSummaryView(viewModel: viewModel.transferQueueViewModel)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.65), lineWidth: 1)
            }
    }

    private func resizeHandle(availableHeight: CGFloat) -> some View {
        Rectangle()
            .fill(Color.clear)
            .frame(height: MainBrowserLayout.resizeHandleHeight)
            .overlay {
                Divider()
            }
            .contentShape(Rectangle())
            .help("Resize Transfer Queue")
            .gesture(
                DragGesture(minimumDistance: 1)
                    .onChanged { value in
                        let startHeight = transferQueueHeightAtDragStart ?? transferQueueHeight
                        transferQueueHeightAtDragStart = startHeight
                        transferQueueHeight = MainBrowserLayout.queueHeight(
                            for: availableHeight,
                            requestedQueueHeight: startHeight - value.translation.height
                        )
                    }
                    .onEnded { value in
                        let startHeight = transferQueueHeightAtDragStart ?? transferQueueHeight
                        transferQueueHeight = MainBrowserLayout.queueHeight(
                            for: availableHeight,
                            requestedQueueHeight: startHeight - value.translation.height
                        )
                        transferQueueHeightAtDragStart = nil
                    }
            )
    }

    private var localPanel: some View {
        FilePanelView(
            state: viewModel.localPanel,
            action: FilePanelAction(
                title: "Upload",
                systemImage: "arrow.up.to.line",
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
                        isEnabled: viewModel.selectedHost != nil,
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
            onCopyDebugDetail: viewModel.copyLocalDebugDetail,
            onRefresh: viewModel.refreshLocal,
            onGoUp: viewModel.goUpLocal,
            onPathSubmit: viewModel.enterLocalPath,
            onSelect: { item, intent in
                viewModel.selectLocalItem(item, intent: intent)
            },
            onOpen: viewModel.openLocalItem
        )
    }

    private func runIdleSessionCleanupLoop() async {
        while !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
            await viewModel.disconnectIdleSessions()
        }
    }

    private var remotePanel: some View {
        FilePanelView(
            state: viewModel.remotePanel,
            action: FilePanelAction(
                title: "Download",
                systemImage: "arrow.down.to.line",
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
                        isEnabled: viewModel.selectedHost != nil,
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
            onCopyDebugDetail: viewModel.copyRemoteDebugDetail,
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
            onPathSubmit: { path in
                Task {
                    await viewModel.enterRemotePath(path)
                }
            },
            onSelect: { item, intent in
                viewModel.selectRemoteItem(item, intent: intent)
            },
            onOpen: { item in
                Task {
                    await viewModel.openRemoteItem(item)
                }
            }
        )
    }
}
