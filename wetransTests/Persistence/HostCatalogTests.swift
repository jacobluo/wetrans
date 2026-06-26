import XCTest
@testable import wetrans

final class HostCatalogTests: XCTestCase {
    func testSaveLoadAndUpdateHost() throws {
        let catalog = makeCatalog()
        let host = try HostDraft.validManualFixture().makeSavedHost()
        let connectedAt = Date(timeIntervalSince1970: 1_782_461_000)

        try catalog.save(host)
        try catalog.markConnected(hostId: host.id, at: connectedAt)
        try catalog.updatePaths(hostId: host.id, local: "/Users/example/Downloads", remote: "/var/www")
        try catalog.setFavorite(hostId: host.id, isFavorite: true)

        let saved = try XCTUnwrap(catalog.load().first)
        XCTAssertEqual(saved.id, host.id)
        XCTAssertEqual(saved.lastConnectedAt, connectedAt)
        XCTAssertEqual(saved.lastLocalPath, "/Users/example/Downloads")
        XCTAssertEqual(saved.lastRemotePath, "/var/www")
        XCTAssertTrue(saved.isFavorite)
    }

    func testDeleteRemovesHost() throws {
        let catalog = makeCatalog()
        let host = try HostDraft.validManualFixture().makeSavedHost()

        try catalog.save(host)
        try catalog.delete(hostId: host.id)

        XCTAssertEqual(try catalog.load(), [])
    }

    func testUnsupportedSchemaVersionFailsWithReadableError() throws {
        let url = temporaryDirectory().appendingPathComponent("hosts.json")
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try #"{"schemaVersion":999,"hosts":[]}"#.data(using: .utf8)!.write(to: url)
        let catalog = FileHostCatalog(store: JSONDocumentStore(url: url))

        XCTAssertThrowsError(try catalog.load()) { error in
            XCTAssertEqual(error as? JSONDocumentStoreError, .unsupportedSchemaVersion(999))
        }
    }

    private func makeCatalog() -> FileHostCatalog {
        FileHostCatalog(applicationSupportDirectory: temporaryDirectory())
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wetrans-tests")
            .appendingPathComponent(UUID().uuidString)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

