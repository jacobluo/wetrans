import SwiftUI
import wetrans

struct ContentView: View {
    @StateObject private var sidebarViewModel = HostSidebarViewModel()
    @State private var isShowingConnectHost = false

    var body: some View {
        NavigationSplitView {
            HostSidebarView(viewModel: sidebarViewModel) {
                isShowingConnectHost = true
            }
        } detail: {
            HSplitView {
                FilePanelPlaceholder(title: "Local Files", path: "~/Downloads")
                FilePanelPlaceholder(title: "Remote Files", path: "Not connected")
            }
            .safeAreaInset(edge: .bottom) {
                TransferQueuePlaceholder()
            }
        }
        .sheet(isPresented: $isShowingConnectHost) {
            ConnectHostDialogView()
        }
    }
}

private struct FilePanelPlaceholder: View {
    let title: String
    let path: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding()

            Divider()

            ContentUnavailableView(
                title,
                systemImage: "folder",
                description: Text("File browsing will be wired after host onboarding.")
            )
        }
        .frame(minWidth: 320)
    }
}

private struct TransferQueuePlaceholder: View {
    var body: some View {
        HStack {
            Label("Transfer Queue", systemImage: "arrow.up.arrow.down")
            Spacer()
            Text("No tasks")
                .foregroundStyle(.secondary)
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
    }
}
