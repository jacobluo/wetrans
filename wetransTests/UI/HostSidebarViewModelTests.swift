import XCTest
@testable import wetrans

final class HostSidebarViewModelTests: XCTestCase {
    func testGroupsHostsByFavoriteRecentThenMyHostsWithoutDuplicates() {
        let favorite = SavedHost.fixture(
            displayName: "fav",
            isFavorite: true,
            lastConnectedAt: Date(timeIntervalSince1970: 10)
        )
        let recent = SavedHost.fixture(
            displayName: "recent",
            isFavorite: false,
            lastConnectedAt: Date(timeIntervalSince1970: 20)
        )
        let mine = SavedHost.fixture(displayName: "mine", isFavorite: false, lastConnectedAt: nil)

        let groups = HostSidebarViewModel.makeGroups(hosts: [mine, recent, favorite])

        XCTAssertEqual(groups.favorites.map(\.displayName), ["fav"])
        XCTAssertEqual(groups.recent.map(\.displayName), ["recent"])
        XCTAssertEqual(groups.myHosts.map(\.displayName), ["mine"])
    }

    func testRecentHostsAreSortedAndLimited() {
        let hosts = (0..<12).map {
            SavedHost.fixture(
                displayName: "h\($0)",
                isFavorite: false,
                lastConnectedAt: Date(timeIntervalSince1970: TimeInterval($0))
            )
        }

        let groups = HostSidebarViewModel.makeGroups(hosts: hosts)

        XCTAssertEqual(groups.recent.count, 10)
        XCTAssertEqual(groups.recent.first?.displayName, "h11")
        XCTAssertEqual(groups.recent.last?.displayName, "h2")
    }

    func testSelectionIsClearedWhenSelectedHostDisappears() {
        let host = SavedHost.fixture(displayName: "dev", isFavorite: false, lastConnectedAt: nil)
        let viewModel = HostSidebarViewModel(hosts: [host])

        viewModel.select(host: host)
        viewModel.update(hosts: [])

        XCTAssertNil(viewModel.selectedHostId)
    }
}

private extension SavedHost {
    static func fixture(displayName: String, isFavorite: Bool, lastConnectedAt: Date?) -> SavedHost {
        SavedHost(
            source: .manual,
            displayName: displayName,
            hostname: "\(displayName).example.com",
            username: "ubuntu",
            authType: .password,
            isFavorite: isFavorite,
            lastConnectedAt: lastConnectedAt
        )
    }
}

