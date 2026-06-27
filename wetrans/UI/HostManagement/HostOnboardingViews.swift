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
                    .font(.system(size: 13, weight: .medium))
                    .frame(maxWidth: .infinity, minHeight: 32)
            }
            .accessibilityIdentifier("Connect Host")
            .buttonStyle(.bordered)
            .controlSize(.regular)
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
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("Host Row \(host.displayName)")
        .accessibilityLabel(host.displayName)
        .accessibilityAddTraits(.isButton)
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

public struct SavedHostDetailRow: Equatable, Sendable {
    public var label: String
    public var value: String

    public init(label: String, value: String) {
        self.label = label
        self.value = value
    }
}

public struct SavedHostsManagementState: Equatable, Sendable {
    public var hosts: [SavedHost]
    public var selectedHostId: UUID?
    public var searchText: String

    public init(hosts: [SavedHost] = [], selectedHostId: UUID? = nil, searchText: String = "") {
        self.hosts = hosts
        self.selectedHostId = selectedHostId
        self.searchText = searchText
    }

    public var filteredHosts: [SavedHost] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return hosts
        }
        return hosts.filter { host in
            host.displayName.localizedCaseInsensitiveContains(query) ||
                host.hostname.localizedCaseInsensitiveContains(query) ||
                host.username.localizedCaseInsensitiveContains(query)
        }
    }

    public var selectedHost: SavedHost? {
        guard let selectedHostId else {
            return nil
        }
        return hosts.first { $0.id == selectedHostId }
    }

    public mutating func ensureValidSelection() {
        if let selectedHostId, hosts.contains(where: { $0.id == selectedHostId }) {
            return
        }
        selectedHostId = hosts.first?.id
    }

    public func detailRows(for host: SavedHost) -> [SavedHostDetailRow] {
        [
            SavedHostDetailRow(label: "Display name", value: host.displayName),
            SavedHostDetailRow(label: "Host / IP", value: host.hostname),
            SavedHostDetailRow(label: "Username", value: host.username),
            SavedHostDetailRow(label: "Port", value: String(host.port)),
            SavedHostDetailRow(label: "Auth type", value: host.authType == .sshKey ? "SSH key" : "Password"),
            SavedHostDetailRow(label: "Identity file", value: host.identityFile?.trimmedNilIfEmpty ?? "-"),
            SavedHostDetailRow(label: "Default remote path", value: host.defaultRemotePath?.trimmedNilIfEmpty ?? "-"),
            SavedHostDetailRow(label: "Last remote path", value: host.lastRemotePath?.trimmedNilIfEmpty ?? "-"),
            SavedHostDetailRow(label: "Source", value: sourceDescription(for: host)),
            SavedHostDetailRow(label: "Note", value: host.note?.trimmedNilIfEmpty ?? "-")
        ]
    }

    public func statusText(for host: SavedHost) -> String {
        [
            host.isFavorite ? "Favorite" : nil,
            host.lastConnectedAt == nil ? "Not connected" : "Connected",
            "Secrets stored in Keychain"
        ]
        .compactMap { $0 }
        .joined(separator: " • ")
    }

    private func sourceDescription(for host: SavedHost) -> String {
        switch host.source {
        case .manual:
            return "Manual saved host"
        case .sshConfigGenerated:
            if let alias = host.originSSHConfigAlias?.trimmedNilIfEmpty {
                return "SSH Config alias \(alias) -> saved host"
            }
            return "SSH Config generated -> saved host"
        }
    }
}

public enum ConnectHostLayout {
    public static let headerSpacing: CGFloat = 4
    public static let contentSpacing: CGFloat = 12
    public static let optionCardSpacing: CGFloat = 12
    public static let optionCardHeight: CGFloat = 118
    public static let sheetPadding: CGFloat = 20
    public static let savedHostActionButtonMinWidth: CGFloat = 70
    public static let savedHostActionButtonMinHeight: CGFloat = 26
}

public struct ConnectHostDialogView: View {
    @Binding private var savedHostsState: SavedHostsManagementState
    @Binding private var editingHost: SavedHost?
    private let onManualAdd: () -> Void
    private let onSelectSSHConfig: () -> Void
    private let onDeleteHost: (SavedHost) -> Void
    private let onToggleFavorite: (SavedHost) -> Void
    private let onSaveHost: (SavedHost) -> Void
    private let managementErrorMessage: String?

    public init(
        savedHostsState: Binding<SavedHostsManagementState> = .constant(SavedHostsManagementState()),
        editingHost: Binding<SavedHost?> = .constant(nil),
        managementErrorMessage: String? = nil,
        onManualAdd: @escaping () -> Void = {},
        onSelectSSHConfig: @escaping () -> Void = {},
        onDeleteHost: @escaping (SavedHost) -> Void = { _ in },
        onToggleFavorite: @escaping (SavedHost) -> Void = { _ in },
        onSaveHost: @escaping (SavedHost) -> Void = { _ in }
    ) {
        self._savedHostsState = savedHostsState
        self._editingHost = editingHost
        self.managementErrorMessage = managementErrorMessage
        self.onManualAdd = onManualAdd
        self.onSelectSSHConfig = onSelectSSHConfig
        self.onDeleteHost = onDeleteHost
        self.onToggleFavorite = onToggleFavorite
        self.onSaveHost = onSaveHost
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: ConnectHostLayout.contentSpacing) {
            VStack(alignment: .leading, spacing: ConnectHostLayout.headerSpacing) {
                Text("Connect Host")
                    .font(.system(size: 18, weight: .bold))
                Text("Create a saved host manually or generate one from ~/.ssh/config. SSH Config is used only as a source.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: ConnectHostLayout.optionCardSpacing) {
                ConnectHostOptionCard(
                    title: "Manual Add",
                    description: "Enter server address, username, port, auth method, default path, and note.",
                    buttonTitle: "Start manual",
                    buttonAccessibilityIdentifier: "Manual Add Start",
                    systemImage: "keyboard",
                    isProminent: false,
                    action: onManualAdd
                )
                .accessibilityIdentifier("Manual Add")

                ConnectHostOptionCard(
                    title: "Select from SSH Config",
                    description: "Search plain Host aliases, resolve with ssh -G, then save as a normal host.",
                    buttonTitle: "Browse aliases",
                    buttonAccessibilityIdentifier: "SSH Config Browse Aliases",
                    systemImage: "terminal",
                    isProminent: true,
                    action: onSelectSSHConfig
                )
                .accessibilityIdentifier("Select from SSH Config")
            }

            SavedHostsManagementPanel(
                state: $savedHostsState,
                editingHost: $editingHost,
                errorMessage: managementErrorMessage,
                onDeleteHost: onDeleteHost,
                onToggleFavorite: onToggleFavorite,
                onSaveHost: onSaveHost
            )
        }
        .padding(ConnectHostLayout.sheetPadding)
        .frame(width: 760)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
    }
}

public struct ConnectHostSheetView: View {
    private enum Route {
        case choices
        case manual
        case sshConfig
        case sshConfigDraft
    }

    private let catalog: HostCatalog
    private let credentialStore: CredentialStore
    private let savedHostMaintenance: SavedHostMaintenance
    private let scanner: SSHConfigScanner
    private let resolver: SSHConfigResolver
    private let onSaved: (SavedHost) -> Void

    @State private var route: Route = .choices
    @State private var draft = Self.emptyManualDraft
    @State private var aliases: [SSHConfigAlias] = []
    @State private var searchText = ""
    @State private var isLoadingAliases = false
    @State private var isResolvingAlias = false
    @State private var errorMessage: String?
    @State private var hostManagementErrorMessage: String?
    @State private var savedHostsState = SavedHostsManagementState()
    @State private var editingHost: SavedHost?

    public init(
        catalog: HostCatalog,
        credentialStore: CredentialStore,
        trustedHostStore: TrustedHostStore = FileTrustedHostStore(
            applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory
        ),
        hostSessionCleaner: HostSessionCleaning = NoopHostSessionCleaner(),
        scanner: SSHConfigScanner = FileSSHConfigScanner(),
        resolver: SSHConfigResolver = ProcessSSHConfigResolver(),
        onSaved: @escaping (SavedHost) -> Void
    ) {
        self.catalog = catalog
        self.credentialStore = credentialStore
        self.savedHostMaintenance = SavedHostMaintenance(
            catalog: catalog,
            credentialStore: credentialStore,
            trustedHostStore: trustedHostStore,
            hostSessionCleaner: hostSessionCleaner
        )
        self.scanner = scanner
        self.resolver = resolver
        self.onSaved = onSaved
    }

    public var body: some View {
        Group {
            switch route {
            case .choices:
                ConnectHostDialogView(
                    savedHostsState: $savedHostsState,
                    editingHost: $editingHost,
                    managementErrorMessage: hostManagementErrorMessage,
                    onManualAdd: showManualAdd,
                    onSelectSSHConfig: showSSHConfigAliases,
                    onDeleteHost: deleteSavedHost,
                    onToggleFavorite: toggleFavorite,
                    onSaveHost: saveEditedHost
                )
            case .manual:
                HostDraftEditorView(
                    title: "Manual Add",
                    subtitle: "Create a saved host with server address, username, port, and authentication.",
                    draft: $draft,
                    errorMessage: errorMessage,
                    isSaving: isResolvingAlias,
                    onBack: showChoices,
                    onSave: saveCurrentDraft
                )
            case .sshConfig:
                SSHConfigAliasPickerView(
                    aliases: filteredAliases,
                    searchText: $searchText,
                    isLoading: isLoadingAliases,
                    isResolving: isResolvingAlias,
                    errorMessage: errorMessage,
                    onBack: showChoices,
                    onRefresh: loadAliases,
                    onSelect: resolveAlias
                )
            case .sshConfigDraft:
                HostDraftEditorView(
                    title: "Review SSH Config Host",
                    subtitle: "This host was generated from ~/.ssh/config and will be saved as a normal host.",
                    draft: $draft,
                    errorMessage: errorMessage,
                    isSaving: isResolvingAlias,
                    onBack: showSSHConfigAliases,
                    onSave: saveCurrentDraft
                )
            }
        }
        .frame(width: 760)
        .onAppear(perform: loadSavedHosts)
    }

    private var filteredAliases: [SSHConfigAlias] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else {
            return aliases
        }
        return aliases.filter { $0.alias.localizedCaseInsensitiveContains(query) }
    }

    private func showChoices() {
        route = .choices
        errorMessage = nil
    }

    private func showManualAdd() {
        draft = Self.emptyManualDraft
        route = .manual
        errorMessage = nil
    }

    private func showSSHConfigAliases() {
        route = .sshConfig
        errorMessage = nil
        if aliases.isEmpty {
            loadAliases()
        }
    }

    private func loadAliases() {
        isLoadingAliases = true
        errorMessage = nil
        do {
            aliases = try scanner.scanDefaultConfig()
            if aliases.isEmpty {
                errorMessage = "No selectable Host aliases found in ~/.ssh/config."
            }
        } catch CocoaError.fileReadNoSuchFile {
            errorMessage = "No ~/.ssh/config found. You can add a host manually."
            aliases = []
        } catch {
            errorMessage = readableMessage(for: error)
            aliases = []
        }
        isLoadingAliases = false
    }

    private func resolveAlias(_ alias: SSHConfigAlias) {
        isResolvingAlias = true
        errorMessage = nil
        Task {
            do {
                let resolved = try await resolver.resolve(alias: alias.alias)
                draft = ProcessSSHConfigResolver.makeDraft(from: resolved)
                route = .sshConfigDraft
            } catch {
                errorMessage = readableMessage(for: error)
            }
            isResolvingAlias = false
        }
    }

    private func saveCurrentDraft() {
        isResolvingAlias = true
        errorMessage = nil
        Task {
            do {
                let viewModel = ConnectHostViewModel(
                    catalog: catalog,
                    credentialStore: credentialStore,
                    draft: draft
                )
                try await viewModel.saveDraft()
                if let savedHost = viewModel.savedHost {
                    loadSavedHosts()
                    onSaved(savedHost)
                }
            } catch {
                errorMessage = readableMessage(for: error)
            }
            isResolvingAlias = false
        }
    }

    private func loadSavedHosts() {
        do {
            savedHostsState.hosts = try catalog.load()
            savedHostsState.ensureValidSelection()
            hostManagementErrorMessage = nil
        } catch {
            hostManagementErrorMessage = readableMessage(for: error)
        }
    }

    private func deleteSavedHost(_ host: SavedHost) {
        Task {
            do {
                try await savedHostMaintenance.delete(host)
                if savedHostsState.selectedHostId == host.id {
                    savedHostsState.selectedHostId = nil
                }
                editingHost = nil
                loadSavedHosts()
            } catch {
                hostManagementErrorMessage = readableMessage(for: error)
            }
        }
    }

    private func toggleFavorite(_ host: SavedHost) {
        do {
            try catalog.setFavorite(hostId: host.id, isFavorite: !host.isFavorite)
            loadSavedHosts()
        } catch {
            hostManagementErrorMessage = readableMessage(for: error)
        }
    }

    private func saveEditedHost(_ host: SavedHost) {
        let original = savedHostsState.hosts.first { $0.id == host.id } ?? host
        Task {
            do {
                try await savedHostMaintenance.saveEdited(original: original, edited: host)
                editingHost = nil
                loadSavedHosts()
            } catch {
                hostManagementErrorMessage = readableMessage(for: error)
            }
        }
    }

    private static var emptyManualDraft: HostDraft {
        HostDraft(
            source: .manual,
            displayName: "",
            hostname: "",
            port: 22,
            username: NSUserName(),
            authType: .password
        )
    }
}

private struct SavedHostsManagementPanel: View {
    @Binding var state: SavedHostsManagementState
    @Binding var editingHost: SavedHost?
    @State private var hostPendingDeletion: SavedHost?
    let errorMessage: String?
    let onDeleteHost: (SavedHost) -> Void
    let onToggleFavorite: (SavedHost) -> Void
    let onSaveHost: (SavedHost) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Saved Hosts")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Existing saved hosts. SSH Config aliases appear only after saving.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                TextField("Search saved hosts", text: $state.searchText)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 13))
                    .frame(width: 240)
                    .frame(minHeight: 30)
                    .accessibilityIdentifier("Search Saved Hosts")
            }

            HStack(spacing: 0) {
                savedHostList
                    .frame(width: 205)

                Divider()

                savedHostDetail
                    .frame(maxWidth: .infinity, minHeight: 250, alignment: .topLeading)
            }
            .frame(minHeight: 250)
            .background(.white)
            .overlay {
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
        .accessibilityIdentifier("Saved Hosts Management")
        .alert(
            hostPendingDeletion.map { "Delete \($0.displayName)?" } ?? "Delete Host?",
            isPresented: deleteConfirmationPresented,
            presenting: hostPendingDeletion
        ) { host in
            Button("Delete", role: .destructive) {
                onDeleteHost(host)
                hostPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                hostPendingDeletion = nil
            }
        } message: { _ in
            Text("This removes the saved host and its stored credentials.")
        }
    }

    private var savedHostList: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Hosts")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 10)
                .padding(.vertical, 8)

            if state.filteredHosts.isEmpty {
                Text(state.hosts.isEmpty ? "No saved hosts" : "No matching hosts")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(10)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 3) {
                        ForEach(state.filteredHosts) { host in
                            Button {
                                state.selectedHostId = host.id
                                editingHost = nil
                            } label: {
                                Text(host.isFavorite ? "★ \(host.displayName)" : host.displayName)
                                    .font(.system(size: 12, weight: state.selectedHostId == host.id ? .semibold : .regular))
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 9)
                                    .padding(.vertical, 6)
                                    .background(state.selectedHostId == host.id ? Color(red: 0.843, green: 0.91, blue: 1) : Color.clear)
                                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("Saved Host Row \(host.displayName)")
                        }
                    }
                    .padding(.horizontal, 6)
                    .padding(.bottom, 8)
                }
            }
        }
        .background(Color(red: 0.968, green: 0.976, blue: 0.988))
    }

    @ViewBuilder
    private var savedHostDetail: some View {
        if let editingHost {
            SavedHostInlineEditorView(
                host: Binding(
                    get: { editingHost },
                    set: { self.editingHost = $0 }
                ),
                onCancel: { self.editingHost = nil },
                onSave: {
                    if let editingHost = self.editingHost {
                        onSaveHost(editingHost)
                    }
                }
            )
        } else if let selectedHost = state.selectedHost {
            SavedHostDetailView(
                host: selectedHost,
                rows: state.detailRows(for: selectedHost),
                statusText: state.statusText(for: selectedHost),
                onEdit: { editingHost = selectedHost },
                onDelete: { hostPendingDeletion = selectedHost },
                onToggleFavorite: { onToggleFavorite(selectedHost) }
            )
        } else {
            ContentUnavailableView(
                "No saved host selected",
                systemImage: "server.rack",
                description: Text("Choose a saved host to review or edit it.")
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var deleteConfirmationPresented: Binding<Bool> {
        Binding(
            get: { hostPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    hostPendingDeletion = nil
                }
            }
        )
    }
}

private struct SavedHostDetailView: View {
    let host: SavedHost
    let rows: [SavedHostDetailRow]
    let statusText: String
    let onEdit: () -> Void
    let onDelete: () -> Void
    let onToggleFavorite: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(host.displayName)
                        .font(.system(size: 17, weight: .semibold))
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onToggleFavorite) {
                    Text(host.isFavorite ? "Unfavorite" : "Favorite")
                        .frame(minWidth: 86, minHeight: 26)
                }
                .controlSize(.small)
                    .accessibilityIdentifier("Saved Host Favorite")
                Button(action: onEdit) {
                    Text("Edit")
                        .frame(minWidth: 62, minHeight: 26)
                }
                .controlSize(.small)
                    .accessibilityIdentifier("Saved Host Edit")
                Button(role: .destructive, action: onDelete) {
                    Text("Delete")
                        .frame(minWidth: 70, minHeight: 26)
                }
                .controlSize(.small)
                    .accessibilityIdentifier("Saved Host Delete")
            }

            Text(statusText)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(Color(red: 0.114, green: 0.306, blue: 0.847))
                .padding(.horizontal, 9)
                .padding(.vertical, 5)
                .background(Color(red: 0.918, green: 0.949, blue: 1))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(spacing: 0) {
                ForEach(rows, id: \.label) { row in
                    HStack(alignment: .firstTextBaseline, spacing: 10) {
                        Text(row.label)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 126, alignment: .leading)
                        Text(row.value)
                            .font(.system(size: 11))
                            .foregroundStyle(.primary)
                            .lineLimit(2)
                            .truncationMode(.middle)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .padding(.vertical, 6)
                    if row.label != rows.last?.label {
                        Divider()
                    }
                }
            }
        }
        .padding(14)
    }

    private var subtitle: String {
        switch host.source {
        case .manual:
            return "Manual saved host"
        case .sshConfigGenerated:
            return "SSH Config generated host"
        }
    }
}

private struct SavedHostInlineEditorView: View {
    @Binding var host: SavedHost
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Edit \(host.displayName)")
                        .font(.system(size: 17, weight: .semibold))
                    Text("Secrets stay in Keychain and are not shown here.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Button(action: onCancel) {
                    Text("Cancel")
                        .frame(
                            minWidth: ConnectHostLayout.savedHostActionButtonMinWidth,
                            minHeight: ConnectHostLayout.savedHostActionButtonMinHeight
                        )
                }
                    .controlSize(.small)
                    .accessibilityIdentifier("Saved Host Cancel")
                Button(action: onSave) {
                    Text("Save")
                        .frame(
                            minWidth: ConnectHostLayout.savedHostActionButtonMinWidth,
                            minHeight: ConnectHostLayout.savedHostActionButtonMinHeight
                        )
                }
                    .controlSize(.small)
                    .keyboardShortcut(.defaultAction)
                    .accessibilityIdentifier("Saved Host Save")
            }

            LabeledContent("Display name") {
                TextField("dev", text: $host.displayName)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Host / IP") {
                TextField("example.com", text: $host.hostname)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Username") {
                TextField("ubuntu", text: $host.username)
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Port") {
                TextField("22", text: portBinding)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 120)
            }
            LabeledContent("Authentication") {
                Picker("Authentication", selection: authSelectionBinding) {
                    Text("Password").tag(AuthType.password.rawValue)
                    Text("SSH Key").tag(AuthType.sshKey.rawValue)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(width: 220)
            }
            if host.authType == .sshKey {
                LabeledContent("Identity file") {
                    TextField("~/.ssh/id_ed25519", text: optionalTextBinding(\.identityFile))
                        .textFieldStyle(.roundedBorder)
                }
            }
            LabeledContent("Default remote path") {
                TextField("/home/user", text: optionalTextBinding(\.defaultRemotePath))
                    .textFieldStyle(.roundedBorder)
            }
            LabeledContent("Note") {
                TextField("Note", text: optionalTextBinding(\.note), axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(2, reservesSpace: true)
            }
        }
        .padding(14)
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { String(host.port) },
            set: { host.port = Int($0) ?? 0 }
        )
    }

    private var authSelectionBinding: Binding<String> {
        Binding(
            get: { host.authType.rawValue },
            set: { host.authType = AuthType(rawValue: $0) ?? .password }
        )
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<SavedHost, String?>) -> Binding<String> {
        Binding(
            get: { host[keyPath: keyPath] ?? "" },
            set: { host[keyPath: keyPath] = $0 }
        )
    }
}

private struct HostDraftEditorView: View {
    let title: String
    let subtitle: String
    @Binding var draft: HostDraft
    let errorMessage: String?
    let isSaving: Bool
    let onBack: () -> Void
    let onSave: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeaderView(title: title, subtitle: subtitle, onBack: onBack)

            VStack(alignment: .leading, spacing: 12) {
                LabeledContent("Display name") {
                    TextField("dev", text: $draft.displayName)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(accessibilityPrefix) Display Name")
                }
                LabeledContent("Host / IP") {
                    TextField("example.com", text: $draft.hostname)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(accessibilityPrefix) Hostname")
                }
                LabeledContent("Port") {
                    TextField("22", text: portBinding)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .accessibilityIdentifier("\(accessibilityPrefix) Port")
                }
                LabeledContent("Username") {
                    TextField(NSUserName(), text: $draft.username)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(accessibilityPrefix) Username")
                }
                LabeledContent("Authentication") {
                    Picker("Authentication", selection: authSelectionBinding) {
                        Text("Password").tag(AuthType.password.rawValue)
                            .accessibilityIdentifier("\(accessibilityPrefix) Auth Password")
                        Text("SSH Key").tag(AuthType.sshKey.rawValue)
                            .accessibilityIdentifier("\(accessibilityPrefix) Auth SSH Key")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 220)
                    .accessibilityIdentifier("\(accessibilityPrefix) Authentication")
                }

                if draft.authType == .sshKey {
                    LabeledContent("Identity file") {
                        TextField("~/.ssh/id_ed25519", text: optionalTextBinding(\.identityFile))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("\(accessibilityPrefix) Identity File")
                    }
                    LabeledContent("Key passphrase") {
                        SecureField("Stored in Keychain", text: optionalTextBinding(\.keyPassphrase))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("\(accessibilityPrefix) Key Passphrase")
                    }
                } else {
                    LabeledContent("Password") {
                        SecureField("Stored in Keychain", text: optionalTextBinding(\.password))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityIdentifier("\(accessibilityPrefix) Password")
                    }
                }

                LabeledContent("Default remote path") {
                    TextField("/home/user", text: optionalTextBinding(\.defaultRemotePath))
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("\(accessibilityPrefix) Default Remote Path")
                }
            }

            if !draft.unsupportedOptions.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(draft.unsupportedOptions, id: \.key) { warning in
                        Label(warning.message, systemImage: "exclamationmark.triangle")
                            .font(.system(size: 11))
                            .foregroundStyle(.orange)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }

            HStack {
                Spacer()
                Button("Save Host", action: onSave)
                    .keyboardShortcut(.defaultAction)
                    .disabled(isSaving)
                    .accessibilityIdentifier("\(accessibilityPrefix) Save")
                if isSaving {
                    ProgressView()
                        .controlSize(.small)
                }
            }
        }
        .padding(24)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
        .accessibilityIdentifier("\(accessibilityPrefix) Form")
    }

    private var accessibilityPrefix: String {
        title == "Manual Add" ? "Manual Host" : "SSH Config Host"
    }

    private var portBinding: Binding<String> {
        Binding(
            get: { String(draft.port) },
            set: { draft.port = Int($0) ?? 0 }
        )
    }

    private var authSelectionBinding: Binding<String> {
        Binding(
            get: { draft.authType.rawValue },
            set: { draft.authType = AuthType(rawValue: $0) ?? .password }
        )
    }

    private func optionalTextBinding(_ keyPath: WritableKeyPath<HostDraft, String?>) -> Binding<String> {
        Binding(
            get: { draft[keyPath: keyPath] ?? "" },
            set: { draft[keyPath: keyPath] = $0 }
        )
    }
}

private struct SSHConfigAliasPickerView: View {
    let aliases: [SSHConfigAlias]
    @Binding var searchText: String
    let isLoading: Bool
    let isResolving: Bool
    let errorMessage: String?
    let onBack: () -> Void
    let onRefresh: () -> Void
    let onSelect: (SSHConfigAlias) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SheetHeaderView(
                title: "Select from SSH Config",
                subtitle: "Search plain Host aliases, resolve with ssh -G, then save as a normal host.",
                onBack: onBack
            )

            HStack(spacing: 10) {
                TextField("Search aliases", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("SSH Config Search")
                Button("Refresh", action: onRefresh)
                    .disabled(isLoading || isResolving)
                    .accessibilityIdentifier("SSH Config Refresh")
            }

            Group {
                if isLoading {
                    ProgressView("Reading ~/.ssh/config...")
                        .frame(maxWidth: .infinity, minHeight: 220)
                } else if aliases.isEmpty {
                    ContentUnavailableView(
                        "No aliases",
                        systemImage: "terminal",
                        description: Text("No selectable SSH Config Host aliases are available.")
                    )
                    .frame(minHeight: 220)
                } else {
                    List(aliases) { alias in
                        Button {
                            onSelect(alias)
                        } label: {
                            HStack {
                                Image(systemName: "terminal")
                                    .foregroundStyle(.secondary)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(alias.alias)
                                        .font(.system(size: 13, weight: .medium))
                                    if let sourcePath = alias.sourcePath {
                                        Text(sourcePath)
                                            .font(.system(size: 10))
                                            .foregroundStyle(.secondary)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                    }
                                }
                                Spacer()
                            }
                        }
                        .buttonStyle(.plain)
                        .disabled(isResolving)
                        .accessibilityIdentifier("SSH Config Alias \(alias.alias)")
                    }
                    .frame(minHeight: 240)
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundStyle(.red)
            }
        }
        .padding(24)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
        .accessibilityIdentifier("SSH Config Alias Picker")
    }
}

private struct SheetHeaderView: View {
    let title: String
    let subtitle: String
    let onBack: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .controlSize(.small)
            .help("Back")

            VStack(alignment: .leading, spacing: 5) {
                Text(title)
                    .font(.system(size: 20, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

private func readableMessage(for error: Error) -> String {
    switch error {
    case HostValidationError.missingDisplayName:
        return "Display name is required."
    case HostValidationError.missingHostname:
        return "Host / IP is required."
    case HostValidationError.invalidPort:
        return "Port must be between 1 and 65535."
    case HostValidationError.missingUsername:
        return "Username is required."
    case HostValidationError.missingIdentityFile:
        return "Identity file is required for SSH Key authentication."
    case SSHConfigResolverError.missingHostname:
        return "Unable to resolve this SSH Config host."
    case SSHConfigResolverError.invalidPort:
        return "SSH Config resolved an invalid port."
    case SSHConfigResolverError.processFailed:
        return "ssh -G failed for this alias. Check your SSH Config and try again."
    default:
        return error.localizedDescription
    }
}

private struct ConnectHostOptionCard: View {
    let title: String
    let description: String
    let buttonTitle: String
    let buttonAccessibilityIdentifier: String
    let systemImage: String
    let isProminent: Bool
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(.primary)
            Text(description)
                .font(.system(size: 11))
                .foregroundStyle(isProminent ? Color(red: 0.114, green: 0.306, blue: 0.847) : .secondary)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: action) {
                Text(buttonTitle)
                    .font(.system(size: 12, weight: .medium))
                    .frame(minWidth: 116, minHeight: 26)
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
                .accessibilityIdentifier(buttonAccessibilityIdentifier)
        }
        .padding(12)
        .frame(height: ConnectHostLayout.optionCardHeight, alignment: .topLeading)
        .frame(maxWidth: .infinity, alignment: .topLeading)
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
