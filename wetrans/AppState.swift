import Foundation

@MainActor
public final class AppState: ObservableObject {
    @Published public private(set) var selectedHostId: UUID?
    @Published public var isShowingConnectHost: Bool
    @Published public private(set) var isTransferQueueExpanded: Bool
    @Published public private(set) var appErrorMessage: String?

    public init(
        selectedHostId: UUID? = nil,
        isShowingConnectHost: Bool = false,
        isTransferQueueExpanded: Bool = true,
        appErrorMessage: String? = nil
    ) {
        self.selectedHostId = selectedHostId
        self.isShowingConnectHost = isShowingConnectHost
        self.isTransferQueueExpanded = isTransferQueueExpanded
        self.appErrorMessage = appErrorMessage
    }

    public func selectHost(_ hostId: UUID?) {
        selectedHostId = hostId
    }

    public func showConnectHost() {
        isShowingConnectHost = true
    }

    public func dismissConnectHost() {
        isShowingConnectHost = false
    }

    public func setTransferQueueExpanded(_ isExpanded: Bool) {
        isTransferQueueExpanded = isExpanded
    }

    public func showError(_ message: String) {
        appErrorMessage = message
    }

    public func clearError() {
        appErrorMessage = nil
    }
}
