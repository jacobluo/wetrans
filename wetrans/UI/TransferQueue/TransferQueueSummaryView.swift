import SwiftUI

public struct TransferQueueSummaryView: View {
    @ObservedObject private var viewModel: TransferQueueViewModel

    public init(viewModel: TransferQueueViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
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
        }
        .font(.callout)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(.bar)
        .task {
            await viewModel.refresh()
        }
    }
}
