import SwiftUI

public struct FilePanelAction {
    public let title: String
    public let systemImage: String
    public let isEnabled: Bool
    public let perform: () -> Void

    public init(title: String, systemImage: String, isEnabled: Bool, perform: @escaping () -> Void) {
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

public struct FilePanelContextAction: Identifiable {
    public let id: String
    public let title: String
    public let systemImage: String
    public let isEnabled: Bool
    public let perform: () -> Void

    public init(
        id: String,
        title: String,
        systemImage: String,
        isEnabled: Bool,
        perform: @escaping () -> Void
    ) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.isEnabled = isEnabled
        self.perform = perform
    }
}

public struct FilePanelView: View {
    private let state: FilePanelState
    private let action: FilePanelAction?
    private let contextActions: (FileItem) -> [FilePanelContextAction]
    private let onRefresh: () -> Void
    private let onGoUp: () -> Void
    private let onSelect: (FileItem) -> Void
    private let onOpen: (FileItem) -> Void

    public init(
        state: FilePanelState,
        action: FilePanelAction? = nil,
        contextActions: @escaping (FileItem) -> [FilePanelContextAction] = { _ in [] },
        onRefresh: @escaping () -> Void,
        onGoUp: @escaping () -> Void,
        onSelect: @escaping (FileItem) -> Void = { _ in },
        onOpen: @escaping (FileItem) -> Void
    ) {
        self.state = state
        self.action = action
        self.contextActions = contextActions
        self.onRefresh = onRefresh
        self.onGoUp = onGoUp
        self.onSelect = onSelect
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            statusLine
        }
        .frame(minWidth: 320)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
        .accessibilityIdentifier("\(state.title) File Panel")
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                Text(state.path.isEmpty ? " " : state.path)
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let action {
                Button(action: action.perform) {
                    Label(action.title, systemImage: action.systemImage)
                        .labelStyle(.titleAndIcon)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .disabled(!action.isEnabled)
                .help(action.title)
                .accessibilityIdentifier("\(state.title) \(action.title)")
            }

            Button(action: onGoUp) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Go Up")
            .accessibilityIdentifier("\(state.title) Go Up")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.bordered)
            .controlSize(.mini)
            .help("Refresh")
            .accessibilityIdentifier("\(state.title) Refresh")
        }
        .padding(.horizontal, 12)
        .frame(height: 50)
    }

    @ViewBuilder
    private var content: some View {
        switch state.loadingState {
        case .idle:
            ContentUnavailableView(idleTitle, systemImage: "folder", description: Text(idleDescription))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("Empty Folder", systemImage: "folder")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .failed(let message):
            ContentUnavailableView(
                "Could Not Load",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .listing(let listing):
            FilePanelListView(
                panelTitle: state.title,
                listing: listing,
                selectedItemIds: state.selectedItemIds,
                contextActions: contextActions,
                onSelect: onSelect,
                onOpen: onOpen
            )
        }
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 10))
            .foregroundStyle(state.title == "Remote" ? Color(red: 0.216, green: 0.412, blue: 0.659) : .secondary)
            .lineLimit(1)
            .truncationMode(.tail)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .frame(height: 24)
            .background(.background)
    }

    private var statusText: String {
        let selectedCount = state.selectedItemIds.count
        if selectedCount > 0 {
            let noun = selectedCount == 1 ? "selected" : "selected"
            if state.title == "Remote" {
                return "\(selectedCount) \(noun) • downloads target current local directory"
            }
            return "\(selectedCount) \(noun) • uploads target current remote directory"
        }
        if state.title == "Remote" {
            if case .idle = state.loadingState {
                return "Add or select a host to start browsing remote files."
            }
            if case .failed = state.loadingState {
                return "Remote listing failed • keep the last path and retry."
            }
            return "Connected • host key verified • current path remembered per host"
        }
        return "Browse local files and choose upload sources"
    }

    private var idleTitle: String {
        state.title == "Remote" ? "No host selected" : "No Directory Loaded"
    }

    private var idleDescription: String {
        state.title == "Remote" ? "Add or select a host to start browsing remote files." : "Choose a local directory to browse."
    }
}

private struct FilePanelListView: View {
    let panelTitle: String
    let listing: FilePanelListing
    let selectedItemIds: Set<String>
    let contextActions: (FileItem) -> [FilePanelContextAction]
    let onSelect: (FileItem) -> Void
    let onOpen: (FileItem) -> Void

    var body: some View {
        VStack(spacing: 0) {
            tableHeader
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(listing.items) { item in
                        FileItemRow(panelTitle: panelTitle, item: item, isSelected: selectedItemIds.contains(item.id))
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(item)
                            }
                            .onTapGesture(count: 2) {
                                onOpen(item)
                            }
                            .contextMenu {
                                ForEach(contextActions(item)) { action in
                                    Button {
                                        action.perform()
                                    } label: {
                                        Label(action.title, systemImage: action.systemImage)
                                    }
                                    .disabled(!action.isEnabled)
                                }
                            }
                    }
                }
                .padding(.vertical, 3)
            }
        }
    }

    private var tableHeader: some View {
        HStack(spacing: 8) {
            Text("Name")
                .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)
            Text("Size")
                .frame(width: 68, alignment: .trailing)
            Text("Modified")
                .frame(width: 96, alignment: .leading)
            Text("Perms")
                .frame(width: 76, alignment: .leading)
        }
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .bottom) {
            Divider()
        }
    }
}

private struct FileItemRow: View {
    let panelTitle: String
    let item: FileItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 16)

            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(minWidth: 94, maxWidth: .infinity, alignment: .leading)

            Text(sizeText)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 68, alignment: .trailing)

            Text(modifiedText)
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .monospacedDigit()
                .frame(width: 96, alignment: .leading)

            Text(item.permissions ?? "-")
                .foregroundStyle(.secondary)
                .font(.system(size: 11))
                .monospaced()
                .frame(width: 76, alignment: .leading)
        }
        .font(.system(size: 12))
        .padding(.horizontal, 14)
        .frame(height: 28)
        .background(isSelected ? Color(red: 0.863, green: 0.922, blue: 1) : Color.clear)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("\(panelTitle) File Row \(item.name)")
        .accessibilityLabel(item.name)
        .accessibilityAddTraits(.isButton)
    }

    private var sizeText: String {
        guard let size = item.size, !item.isDirectory else {
            return "-"
        }
        return Self.sizeFormatter.string(fromByteCount: Int64(size))
    }

    private var modifiedText: String {
        guard let modifiedAt = item.modifiedAt else {
            return "-"
        }
        return Self.dateFormatter.string(from: modifiedAt)
    }

    private static let sizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter
    }()

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }()
}
