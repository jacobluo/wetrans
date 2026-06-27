import AppKit
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

public enum FilePanelInteractionPolicy {
    public static let usesImmediateSelectionControl = true

    @MainActor
    public static func currentSelectionIntent() -> FilePanelSelectionIntent {
        guard NSApp.currentEvent?.modifierFlags.contains(.shift) == true else {
            return .replace
        }
        return .extend
    }
}

public enum FilePanelToolbarItem: Equatable, Sendable {
    case goUp
    case refresh
    case transfer
}

public enum FilePanelLayout {
    public static let toolbarButtonSide: CGFloat = 24
    public static let toolbarButtonCornerRadius: CGFloat = 5
    public static let transferActionShowsTitle = false
    public static let tableContentMinWidth: CGFloat = 640
    public static let usesSeparateHorizontalAndVerticalScrolling = true
    public static let toolbarOrder: [FilePanelToolbarItem] = [.goUp, .refresh, .transfer]

    public static func systemImage(for item: FilePanelToolbarItem, transferSystemImage: String) -> String {
        switch item {
        case .goUp:
            return "arrow.up"
        case .refresh:
            return "arrow.clockwise"
        case .transfer:
            return transferSystemImage
        }
    }

    public static func helpText(for item: FilePanelToolbarItem, transferTitle: String) -> String {
        switch item {
        case .goUp:
            return "Go to Parent Directory"
        case .refresh:
            return "Refresh"
        case .transfer:
            return transferTitle
        }
    }
}

public struct FilePanelView: View {
    private let state: FilePanelState
    private let action: FilePanelAction?
    private let contextActions: (FileItem) -> [FilePanelContextAction]
    private let onCopyDebugDetail: (() -> Void)?
    private let onRefresh: () -> Void
    private let onGoUp: () -> Void
    private let onPathSubmit: (String) -> Void
    private let onSelect: (FileItem, FilePanelSelectionIntent) -> Void
    private let onOpen: (FileItem) -> Void

    public init(
        state: FilePanelState,
        action: FilePanelAction? = nil,
        contextActions: @escaping (FileItem) -> [FilePanelContextAction] = { _ in [] },
        onCopyDebugDetail: (() -> Void)? = nil,
        onRefresh: @escaping () -> Void,
        onGoUp: @escaping () -> Void,
        onPathSubmit: @escaping (String) -> Void = { _ in },
        onSelect: @escaping (FileItem, FilePanelSelectionIntent) -> Void = { _, _ in },
        onOpen: @escaping (FileItem) -> Void
    ) {
        self.state = state
        self.action = action
        self.contextActions = contextActions
        self.onCopyDebugDetail = onCopyDebugDetail
        self.onRefresh = onRefresh
        self.onGoUp = onGoUp
        self.onPathSubmit = onPathSubmit
        self.onSelect = onSelect
        self.onOpen = onOpen
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            statusLine
        }
        .frame(minWidth: 320, maxHeight: .infinity)
        .background(.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(0.7), lineWidth: 1)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(state.title)
                    .font(.system(size: 12, weight: .semibold))
                    .lineLimit(1)
                    .accessibilityIdentifier("\(state.title) File Panel")
                FilePanelPathField(
                    panelTitle: state.title,
                    path: state.path,
                    onSubmit: onPathSubmit
                )
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Spacer(minLength: 8)

            ForEach(FilePanelLayout.toolbarOrder, id: \.self) { item in
                toolbarButton(for: item)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    @ViewBuilder
    private func toolbarButton(for item: FilePanelToolbarItem) -> some View {
        switch item {
        case .goUp:
            iconButton(
                systemImage: FilePanelLayout.systemImage(for: item, transferSystemImage: ""),
                help: FilePanelLayout.helpText(for: item, transferTitle: ""),
                accessibilityIdentifier: "\(state.title) Go Up",
                isEnabled: true,
                action: onGoUp
            )
        case .refresh:
            iconButton(
                systemImage: FilePanelLayout.systemImage(for: item, transferSystemImage: ""),
                help: FilePanelLayout.helpText(for: item, transferTitle: ""),
                accessibilityIdentifier: "\(state.title) Refresh",
                isEnabled: true,
                action: onRefresh
            )
        case .transfer:
            if let action {
                iconButton(
                    systemImage: FilePanelLayout.systemImage(for: item, transferSystemImage: action.systemImage),
                    help: FilePanelLayout.helpText(for: item, transferTitle: action.title),
                    accessibilityIdentifier: "\(state.title) \(action.title)",
                    isEnabled: action.isEnabled,
                    action: action.perform
                )
            }
        }
    }

    private func iconButton(
        systemImage: String,
        help: String,
        accessibilityIdentifier: String,
        isEnabled: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button {
            guard isEnabled else {
                return
            }
            action()
        } label: {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.45))
                .frame(width: FilePanelLayout.toolbarButtonSide, height: FilePanelLayout.toolbarButtonSide)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(width: FilePanelLayout.toolbarButtonSide, height: FilePanelLayout.toolbarButtonSide)
        .background(isEnabled ? Color(nsColor: .controlBackgroundColor) : Color(nsColor: .controlBackgroundColor).opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: FilePanelLayout.toolbarButtonCornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: FilePanelLayout.toolbarButtonCornerRadius, style: .continuous)
                .stroke(Color(nsColor: .separatorColor).opacity(isEnabled ? 0.7 : 0.35), lineWidth: 1)
        }
        .help(help)
        .accessibilityIdentifier(accessibilityIdentifier)
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
            VStack(spacing: 10) {
                ContentUnavailableView(
                    "Could Not Load",
                    systemImage: "exclamationmark.triangle",
                    description: Text(message)
                )
                if let onCopyDebugDetail {
                    Button {
                        onCopyDebugDetail()
                    } label: {
                        Label("Copy Debug Detail", systemImage: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Debug Detail")
                    .accessibilityIdentifier("\(state.title) Copy Debug Detail")
                }
            }
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

private struct FilePanelPathField: View {
    let panelTitle: String
    let path: String
    let onSubmit: (String) -> Void
    @State private var draftPath: String

    init(panelTitle: String, path: String, onSubmit: @escaping (String) -> Void) {
        self.panelTitle = panelTitle
        self.path = path
        self.onSubmit = onSubmit
        self._draftPath = State(initialValue: path)
    }

    var body: some View {
        TextField("Path", text: $draftPath)
            .textFieldStyle(.roundedBorder)
            .font(.system(size: 11))
            .lineLimit(1)
            .onSubmit {
                onSubmit(draftPath)
            }
            .onChange(of: path) { _, newPath in
                guard newPath != draftPath else {
                    return
                }
                draftPath = newPath
            }
            .accessibilityIdentifier("\(panelTitle) Path")
    }
}

private struct FilePanelListView: View {
    let panelTitle: String
    let listing: FilePanelListing
    let selectedItemIds: Set<String>
    let contextActions: (FileItem) -> [FilePanelContextAction]
    let onSelect: (FileItem, FilePanelSelectionIntent) -> Void
    let onOpen: (FileItem) -> Void

    var body: some View {
        GeometryReader { proxy in
            ScrollView(.horizontal) {
                VStack(spacing: 0) {
                    tableHeader
                    ScrollView(.vertical) {
                        LazyVStack(spacing: 0) {
                            ForEach(listing.items) { item in
                                Button {
                                    onSelect(item, FilePanelInteractionPolicy.currentSelectionIntent())
                                } label: {
                                    FileItemRow(panelTitle: panelTitle, item: item, isSelected: selectedItemIds.contains(item.id))
                                }
                                .buttonStyle(.plain)
                                .contentShape(Rectangle())
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onOpen(item)
                                    }
                                )
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
                    .frame(maxHeight: .infinity)
                }
                .frame(
                    minWidth: max(FilePanelLayout.tableContentMinWidth, proxy.size.width),
                    minHeight: proxy.size.height,
                    alignment: .topLeading
                )
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
