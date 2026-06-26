import SwiftUI

public struct HostSidebarView: View {
    @ObservedObject private var viewModel: HostSidebarViewModel
    private let onConnectHost: () -> Void

    public init(viewModel: HostSidebarViewModel, onConnectHost: @escaping () -> Void) {
        self.viewModel = viewModel
        self.onConnectHost = onConnectHost
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 8) {
                    if viewModel.groups.favorites.isEmpty &&
                        viewModel.groups.recent.isEmpty &&
                        viewModel.groups.myHosts.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "server.rack")
                                .font(.system(size: 28))
                                .foregroundStyle(.secondary)
                            Text("No Hosts")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(.secondary)
                            Text("Connect a host to begin.")
                                .font(.system(size: 10))
                                .foregroundStyle(.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, 54)
                    } else {
                        HostSection(
                            title: "Favorites",
                            hosts: viewModel.groups.favorites,
                            selectedHostId: $viewModel.selectedHostId
                        )
                        HostSection(
                            title: "Recent",
                            hosts: viewModel.groups.recent,
                            selectedHostId: $viewModel.selectedHostId
                        )
                        HostSection(
                            title: "My Hosts",
                            hosts: viewModel.groups.myHosts,
                            selectedHostId: $viewModel.selectedHostId
                        )
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 12)
            }

            Spacer(minLength: 0)

            Button(action: onConnectHost) {
                Text("Connect Host")
                    .font(.system(size: 12, weight: .medium))
                    .frame(maxWidth: .infinity)
            }
            .accessibilityIdentifier("Connect Host")
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 10)
            .padding(.bottom, 8)

            Text("Keychain for secrets")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10)
                .padding(.bottom, 10)
        }
        .background(Color(red: 0.914, green: 0.929, blue: 0.957))
        .overlay(alignment: .trailing) {
            Divider()
        }
    }
}

private struct HostSection: View {
    let title: String
    let hosts: [SavedHost]
    @Binding var selectedHostId: UUID?

    var body: some View {
        if !hosts.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 2)

            ForEach(hosts) { host in
                HostSidebarRow(
                    host: host,
                    isSelected: selectedHostId == host.id
                )
                .onTapGesture {
                    selectedHostId = host.id
                }
            }
        }
    }
}

private struct HostSidebarRow: View {
    let host: SavedHost
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Color(red: 0.059, green: 0.09, blue: 0.165))
                .lineLimit(1)
            Text(metadata)
                .font(.system(size: 10))
                .foregroundStyle(isSelected ? Color(red: 0.145, green: 0.388, blue: 0.922) : .secondary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? Color(red: 0.843, green: 0.91, blue: 1) : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private var title: String {
        host.isFavorite ? "★ \(host.displayName)" : host.displayName
    }

    private var metadata: String {
        if host.lastConnectedAt != nil {
            return "\(host.username)@\(host.hostname)  •  connected"
        }
        switch host.source {
        case .sshConfigGenerated:
            return "ssh config → saved host"
        case .manual:
            return "manual  •  not connected"
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
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Connect Host")
                    .font(.system(size: 20, weight: .bold))
                Text("Create a saved host manually or generate one from ~/.ssh/config. SSH Config is used only as a source.")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 14) {
                ConnectHostOptionCard(
                    title: "Manual Add",
                    description: "Enter server address, username, port, auth method, default path, and note.",
                    buttonTitle: "Start manual",
                    systemImage: "keyboard",
                    isProminent: false,
                    action: onManualAdd
                )
                .accessibilityIdentifier("Manual Add")

                ConnectHostOptionCard(
                    title: "Select from SSH Config",
                    description: "Search plain Host aliases, resolve with ssh -G, then save as a normal host.",
                    buttonTitle: "Browse aliases",
                    systemImage: "terminal",
                    isProminent: true,
                    action: onSelectSSHConfig
                )
                .accessibilityIdentifier("Select from SSH Config")
            }
        }
        .padding(24)
        .frame(width: 720)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
    }
}

private struct ConnectHostOptionCard: View {
    let title: String
    let description: String
    let buttonTitle: String
    let systemImage: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.system(size: 12))
                .foregroundStyle(isProminent ? Color(red: 0.114, green: 0.306, blue: 0.847) : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 8)

            Button(buttonTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
        }
        .frame(maxWidth: .infinity, minHeight: 104, alignment: .topLeading)
        .padding(16)
        .background(cardBackground)
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(cardStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }

    private var cardBackground: Color {
        isProminent ? Color(red: 0.918, green: 0.949, blue: 1) : .white
    }

    private var cardStroke: Color {
        isProminent ? Color(red: 0.514, green: 0.663, blue: 0.91) : Color(nsColor: .separatorColor).opacity(0.7)
    }
}
