import XCTest
@testable import wetrans

final class JSONDocumentStoreTests: XCTestCase {
    func testLoadMissingFileReturnsDefaultDocument() throws {
        let store = JSONDocumentStore<HostsDocument>(
            url: temporaryDirectory().appendingPathComponent("hosts.json")
        )

        XCTAssertEqual(try store.load(default: HostsDocument()), HostsDocument())
    }

    func testSaveCreatesParentDirectoryAndRoundTripsDocument() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("nested")
            .appendingPathComponent("hosts.json")
        let store = JSONDocumentStore<HostsDocument>(url: url)
        let host = try HostDraft.validManualFixture().makeSavedHost(
            id: UUID(uuidString: "8C765C99-6B46-4D74-BB3C-2B71F21997C6")!
        )
        let document = HostsDocument(hosts: [host])

        try store.save(document)

        XCTAssertEqual(try store.load(default: HostsDocument()), document)
        XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
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

