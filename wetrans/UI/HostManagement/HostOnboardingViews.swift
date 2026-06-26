import SwiftUI

public struct HostSidebarView: View {
    @ObservedObject private var viewModel: HostSidebarViewModel
    private let onConnectHost: () -> Void

    public init(viewModel: HostSidebarViewModel, onConnectHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        List(selection: $viewModel.selectedHostId) {
            if viewModel.groups.favorites.isEmpty &&
                viewModel.groups.recent.isEmpty &&
                viewModel.groups.myHosts.isEmpty {
                ContentUnavailableView("No Hosts", systemImage: "server.rack")
            } else {
                HostSection(title: "Favorites", hosts: viewModel.groups.favorites)
                HostSection(title: "Recent", hosts: viewModel.groups.recent)
                HostSection(title: "My Hosts", hosts: viewModel.groups.myHosts)
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .bottom) {
            Button(action: onConnectHost) {
                Label("Connect Host", systemImage: "plus")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityIdentifier("Connect Host")
            .buttonStyle(.borderless)
            .padding(12)
        }
        .navigationSplitViewColumnWidth(min: 220, ideal: 260)
    }
}

private struct HostSection: View {
    let title: String
    let hosts: [SavedHost]

    var body: some View {
        if !hosts.isEmpty {
            Section(title) {
                ForEach(hosts) { host in
                    Label(host.displayName, systemImage: "server.rack")
                        .tag(host.id)
                }
            }
        }
    }
}

public struct ConnectHostDialogView: View {
    private let onManualAdd: () -> Void
    private let onSelectSSHConfig: () -> Void

    public init(
        onManualAdd: @escaping () -> Void = {},
        onSelectSSHConfig: @escaping () -> Void = {}
    ) {
        self.onManualAdd = onManualAdd
        self.onSelectSSHConfig = onSelectSSHConfig
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Connect Host")
                .font(.headline)

            VStack(spacing: 8) {
                Button(action: onManualAdd) {
                    Label("Manual Add", systemImage: "keyboard")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("Manual Add")

                Button(action: onSelectSSHConfig) {
                    Label("Select from SSH Config", systemImage: "terminal")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .accessibilityIdentifier("Select from SSH Config")
            }
            .buttonStyle(.bordered)
        }
        .padding(20)
        .frame(width: 360)
    }
}

