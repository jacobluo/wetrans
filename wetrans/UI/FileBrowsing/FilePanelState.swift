import Foundation

public enum FilePanelLoadingState: Equatable {
    case idle
    case loading
    case loaded([FileItem])
    case empty
    case failed(String)
}

public struct FilePanelState: Equatable {
    public var title: String
    public var path: String
    public var loadingState: FilePanelLoadingState
    public var selectedItemIds: Set<String>

    public init(
        title: String,
        path: String,
        loadingState: FilePanelLoadingState = .idle,
        selectedItemIds: Set<String> = []
    ) {
        self.title = title
        self.path = path
        self.loadingState = loadingState
        self.selectedItemIds = selectedItemIds
    }

    public var errorMessage: String {
        guard case .failed(let message) = loadingState else {
            return ""
        }
        return message
    }

    public var loadedItems: [FileItem] {
        guard case .loaded(let items) = loadingState else {
            return []
        }
        return items
    }

    public var selectedItems: [FileItem] {
        loadedItems.filter { selectedItemIds.contains($0.id) }
    }
}
