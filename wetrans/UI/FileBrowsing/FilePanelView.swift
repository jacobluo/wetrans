import SwiftUI

public struct FilePanelView: View {
    private let state: FilePanelState
    private let onRefresh: () -> Void
    private let onGoUp: () -> Void
    private let onOpen: (FileItem) -> Void

    public init(
        state: FilePanelState,
        onRefresh: @escaping () -> Void,
        onGoUp: @escaping () -> Void,
        onOpen: @escaping (FileItem) -> Void
    ) {
        self.state = state
        self.onRefresh = onRefresh
        self.onGoUp = onGoUp
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
                .onTapGesture(count: 2) {
                    onOpen(item)
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
