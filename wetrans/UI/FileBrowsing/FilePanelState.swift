import Foundation

public enum FilePanelSelectionIntent: Equatable, Sendable {
    case replace
    case extend
}

public struct FilePanelListing: Equatable, Sendable {
    public let fingerprint: Int
    public let items: [FileItem]

    public init(items: [FileItem], fingerprint: Int? = nil) {
        self.items = items
        self.fingerprint = fingerprint ?? Self.makeFingerprint(for: items)
    }

    public static func == (lhs: FilePanelListing, rhs: FilePanelListing) -> Bool {
        lhs.fingerprint == rhs.fingerprint
    }

    private static func makeFingerprint(for items: [FileItem]) -> Int {
        var hasher = Hasher()
        hasher.combine(items.count)
        for item in items {
            hasher.combine(item.id)
            hasher.combine(item.name)
            hasher.combine(item.isDirectory)
            hasher.combine(item.isSymlink)
            hasher.combine(item.size)
            hasher.combine(item.modifiedAt)
            hasher.combine(item.permissions)
        }
        return hasher.finalize()
    }
}

public enum FilePanelLoadingState: Equatable {
    case idle
    case loading
    case listing(FilePanelListing)
    case empty
    case failed(String)

    public static func loaded(_ items: [FileItem]) -> FilePanelLoadingState {
        .listing(FilePanelListing(items: items))
    }
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
        guard case .listing(let listing) = loadingState else {
            return []
        }
        return listing.items
    }

    public var selectedItems: [FileItem] {
        loadedItems.filter { selectedItemIds.contains($0.id) }
    }
}
