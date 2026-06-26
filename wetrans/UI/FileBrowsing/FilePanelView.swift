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
        }
        .frame(minWidth: 320)
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 3) {
                Text(state.title)
                    .font(.headline)
                    .lineLimit(1)
                Text(state.path.isEmpty ? " " : state.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }

            Spacer(minLength: 8)

            if let action {
                Button(action: action.perform) {
                    Image(systemName: action.systemImage)
                }
                .buttonStyle(.borderless)
                .disabled(!action.isEnabled)
                .help(action.title)
            }

            Button(action: onGoUp) {
                Image(systemName: "arrow.up")
            }
            .buttonStyle(.borderless)
            .help("Go Up")

            Button(action: onRefresh) {
                Image(systemName: "arrow.clockwise")
            }
            .buttonStyle(.borderless)
            .help("Refresh")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    @ViewBuilder
    private var content: some View {
        switch state.loadingState {
        case .idle:
            ContentUnavailableView("No Directory Loaded", systemImage: "folder")
        case .loading:
            ProgressView()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .empty:
            ContentUnavailableView("Empty Folder", systemImage: "folder")
        case .failed(let message):
            ContentUnavailableView(
                "Could Not Load",
                systemImage: "exclamationmark.triangle",
                description: Text(message)
            )
        case .loaded(let items):
            fileList(items)
        }
    }

    private func fileList(_ items: [FileItem]) -> some View {
        List(items) { item in
            FileItemRow(item: item)
                .contentShape(Rectangle())
                .listRowBackground(state.selectedItemIds.contains(item.id) ? Color.accentColor.opacity(0.16) : Color.clear)
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
        .listStyle(.inset)
    }
}

private struct FileItemRow: View {
    let item: FileItem

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: item.isDirectory ? "folder" : "doc")
                .foregroundStyle(item.isDirectory ? .blue : .secondary)
                .frame(width: 18)

            Text(item.name)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if let size = item.size, !item.isDirectory {
                Text(Self.sizeFormatter.string(fromByteCount: Int64(size)))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .monospacedDigit()
            }

            if let modifiedAt = item.modifiedAt {
                Text(Self.dateFormatter.string(from: modifiedAt))
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .monospacedDigit()
            }

            if let permissions = item.permissions {
                Text(permissions)
                    .foregroundStyle(.secondary)
                    .font(.caption)
                    .monospaced()
            }
        }
        .padding(.vertical, 2)
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
