import AppKit
import SwiftUI

public struct TransferQueueSummaryView: View {
    @ObservedObject private var viewModel: TransferQueueViewModel

    public init(viewModel: TransferQueueViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        VStack(spacing: 0) {
            if viewModel.isExpanded {
                expandedPanel
            } else {
                collapsedBar
            }
        }
        .background(.background)
        .task {
            await viewModel.refresh()
        }
        .accessibilityIdentifier("Transfer Queue")
    }

    private var collapsedBar: some View {
        HStack(spacing: 12) {
            Label("Transfer Queue", systemImage: "arrow.up.arrow.down")
                .fontWeight(.medium)

            Text(viewModel.summaryText)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer(minLength: 12)

            if viewModel.summary.failedCount > 0 {
                Label("\(viewModel.summary.failedCount)", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .labelStyle(.titleAndIcon)
            }

            Button {
                viewModel.toggleExpanded()
            } label: {
                Image(systemName: "chevron.up")
            }
            .buttonStyle(.borderless)
            .help("Expand Transfer Queue")
            .accessibilityIdentifier("Transfer Queue Expand")
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var expandedPanel: some View {
        VStack(spacing: 0) {
            expandedHeader
            Divider()
            queueHeader

            if viewModel.rows.isEmpty {
                Text("No transfers yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 86)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(viewModel.rows) { row in
                            TransferQueueTaskRow(
                                row: row,
                                onAction: { action in
                                    perform(action, taskId: row.id)
                                },
                                onCopyError: { message in
                                    copyError(message)
                                }
                            )
                            .accessibilityIdentifier("Transfer Row \(row.fileName)")
                        }
                    }
                }
                .frame(maxHeight: 108)
            }

            Divider()
            HStack {
                Text("Global 3 running · per-host 2 · survives host switching")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .font(.caption)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
        }
    }

    private var expandedHeader: some View {
        HStack(spacing: 10) {
            Text("Transfer Queue")
                .fontWeight(.semibold)

            if viewModel.summary.runningCount > 0 {
                QueueBadge(text: "Running \(viewModel.summary.runningCount)", style: .running)
            }

            if viewModel.summary.failedCount > 0 {
                QueueBadge(text: "Failed \(viewModel.summary.failedCount)", style: .failed)
            }

            Spacer(minLength: 12)

            Menu {
                Button("Clear Succeeded") {
                    Task { await viewModel.clearSucceeded() }
                }
                Button("Clear Failed") {
                    Task { await viewModel.clearFailedAndCancelled() }
                }
                Divider()
                Button("Clear Finished") {
                    Task { await viewModel.clearFinished() }
                }
            } label: {
                Label("Clear", systemImage: "trash")
            }
            .menuStyle(.borderlessButton)
            .help("Clear finished transfers")
            .accessibilityIdentifier("Transfer Queue Clear")

            Button {
                viewModel.toggleExpanded()
            } label: {
                Image(systemName: "chevron.down")
            }
            .buttonStyle(.borderless)
            .help("Collapse Transfer Queue")
            .accessibilityIdentifier("Transfer Queue Collapse")
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
    }

    private var queueHeader: some View {
        HStack(spacing: 10) {
            Text("File")
                .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)
            Text("Host")
                .frame(width: 96, alignment: .leading)
            Text("Direction")
                .frame(width: 78, alignment: .leading)
            Text("Progress")
                .frame(width: 116, alignment: .leading)
            Text("Speed")
                .frame(width: 86, alignment: .leading)
            Text("Status")
                .frame(width: 82, alignment: .leading)
            Text("Action")
                .frame(width: 116, alignment: .trailing)
        }
        .font(.caption.weight(.medium))
        .foregroundStyle(.secondary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color(red: 0.973, green: 0.98, blue: 0.988))
    }

    private func perform(_ action: TransferQueueRowAction, taskId: UUID) {
        Task {
            switch action {
            case .cancel:
                await viewModel.cancel(taskId: taskId)
            case .retry:
                await viewModel.retry(taskId: taskId)
            case .remove:
                await viewModel.remove(taskId: taskId)
            }
        }
    }

    private func copyError(_ message: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(message, forType: .string)
    }
}

private struct TransferQueueTaskRow: View {
    let row: TransferQueueRowViewState
    let onAction: (TransferQueueRowAction) -> Void
    let onCopyError: (String) -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Text(row.fileName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(minWidth: 170, maxWidth: .infinity, alignment: .leading)

                Text(row.hostName)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(.secondary)
                    .frame(width: 96, alignment: .leading)

                Text(row.directionText)
                    .frame(width: 78, alignment: .leading)

                HStack(spacing: 6) {
                    ProgressView(value: row.progressValue)
                        .controlSize(.small)
                    Text(row.progressText)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .frame(width: 34, alignment: .trailing)
                }
                .frame(width: 116, alignment: .leading)

                Text(row.speedText)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .frame(width: 86, alignment: .leading)

                Text(row.statusText)
                    .foregroundStyle(row.isFailed ? .red : .secondary)
                    .frame(width: 82, alignment: .leading)

                actionButtons
                    .frame(width: 116, alignment: .trailing)
            }
            .font(.callout)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(row.isFailed ? Color(red: 1, green: 0.969, blue: 0.91) : Color.clear)

            if let errorMessage = row.errorMessage, !errorMessage.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                    Text(errorMessage)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .foregroundStyle(.secondary)
                    Button {
                        onCopyError(errorMessage)
                    } label: {
                        Image(systemName: "doc.on.doc")
                    }
                    .buttonStyle(.borderless)
                    .help("Copy Error")
                    Spacer(minLength: 0)
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.bottom, 7)
                .background(Color(red: 1, green: 0.969, blue: 0.91))
            }

            Divider()
                .padding(.leading, 12)
        }
    }

    @ViewBuilder
    private var actionButtons: some View {
        HStack(spacing: 6) {
            if let primaryAction = row.primaryAction {
                Button(primaryAction.title) {
                    onAction(primaryAction)
                }
                .buttonStyle(.borderless)
                .help(primaryAction.helpText)
            }

            if row.canRemove, row.primaryAction != .remove {
                Button {
                    onAction(.remove)
                } label: {
                    Image(systemName: "xmark.circle")
                }
                .buttonStyle(.borderless)
                .help("Remove Transfer")
            }
        }
    }
}

private struct QueueBadge: View {
    enum Style {
        case running
        case failed
    }

    let text: String
    let style: Style

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(background)
            .foregroundStyle(foreground)
            .clipShape(Capsule())
    }

    private var background: Color {
        switch style {
        case .running:
            return Color.accentColor.opacity(0.14)
        case .failed:
            return Color.red.opacity(0.14)
        }
    }

    private var foreground: Color {
        switch style {
        case .running:
            return .accentColor
        case .failed:
            return .red
        }
    }
}

private extension TransferQueueRowAction {
    var title: String {
        switch self {
        case .cancel:
            return "Cancel"
        case .retry:
            return "Retry"
        case .remove:
            return "Remove"
        }
    }

    var helpText: String {
        switch self {
        case .cancel:
            return "Cancel Transfer"
        case .retry:
            return "Retry Transfer"
        case .remove:
            return "Remove Transfer"
        }
    }
}
