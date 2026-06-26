import Combine
import Foundation

public struct HostSidebarGroups: Equatable {
    public var favorites: [SavedHost]
    public var recent: [SavedHost]
    public var myHosts: [SavedHost]

    public init(favorites: [SavedHost] = [], recent: [SavedHost] = [], myHosts: [SavedHost] = []) {
        self.favorites = favorites
        self.recent = recent
        self.myHosts = myHosts
    }
}

public final class HostSidebarViewModel: ObservableObject {
    @Published public private(set) var groups = HostSidebarGroups()
    @Published public var selectedHostId: UUID?

    public init(hosts: [SavedHost] = []) {
        update(hosts: hosts)
    }

    public func update(hosts: [SavedHost]) {
        groups = Self.makeGroups(hosts: hosts)
        if let selectedHostId, !hosts.contains(where: { $0.id == selectedHostId }) {
            self.selectedHostId = nil
        }
    }

    public func select(host: SavedHost) {
        selectedHostId = host.id
    }

    public static func makeGroups(hosts: [SavedHost]) -> HostSidebarGroups {
        let favorites = hosts
            .filter(\.isFavorite)
            .sorted(by: byDisplayName)

        let recent = hosts
            .filter { !$0.isFavorite && $0.lastConnectedAt != nil }
            .sorted {
                guard $0.lastConnectedAt != $1.lastConnectedAt else {
                    return byDisplayName($0, $1)
                }
                return ($0.lastConnectedAt ?? .distantPast) > ($1.lastConnectedAt ?? .distantPast)
            }
            .prefix(10)

        let myHosts = hosts
            .filter { !$0.isFavorite && $0.lastConnectedAt == nil }
            .sorted(by: byDisplayName)

        return HostSidebarGroups(
            favorites: favorites,
            recent: Array(recent),
            myHosts: myHosts
        )
    }
}

private func byDisplayName(_ lhs: SavedHost, _ rhs: SavedHost) -> Bool {
    lhs.displayName.localizedCaseInsensitiveCompare(rhs.displayName) == .orderedAscending
}
