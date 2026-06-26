import XCTest
@testable import wetrans

final class FileManagerLocalFileSystemTests: XCTestCase {
    func testListsDirectoryWithDirectoriesFirstAndFileMetadata() throws {
        let directory = temporaryDirectory()
        let folderURL = directory.appendingPathComponent("folder")
        let fileURL = directory.appendingPathComponent("file.txt")
        try FileManager.default.createDirectory(at: folderURL, withIntermediateDirectories: true)
        try Data("hello".utf8).write(to: fileURL)

        let items = try FileManagerLocalFileSystem().listDirectory(directory.path)

        XCTAssertEqual(items.map(\.name), ["folder", "file.txt"])
        XCTAssertTrue(items[0].isDirectory)
        XCTAssertFalse(items[1].isDirectory)
        XCTAssertEqual(items[1].size, 5)
        XCTAssertNotNil(items[1].modifiedAt)
    }

    func testMarksSymlinks() throws {
        let directory = temporaryDirectory()
        let targetURL = directory.appendingPathComponent("target.txt")
        let linkURL = directory.appendingPathComponent("link.txt")
        try Data("target".utf8).write(to: targetURL)
        try FileManager.default.createSymbolicLink(at: linkURL, withDestinationURL: targetURL)

        let items = try FileManagerLocalFileSystem().listDirectory(directory.path)

        XCTAssertEqual(items.first { $0.name == "link.txt" }?.isSymlink, true)
    }

    func testThrowsWhenPathIsNotDirectory() throws {
        let directory = temporaryDirectory()
        let fileURL = directory.appendingPathComponent("file.txt")
        try Data("hello".utf8).write(to: fileURL)

        XCTAssertThrowsError(try FileManagerLocalFileSystem().listDirectory(fileURL.path)) { error in
            XCTAssertEqual(error as? LocalFileSystemError, .notDirectory(fileURL.path))
        }
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("wetrans-tests")
            .appendingPathComponent(UUID().uuidString)
        try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        addTeardownBlock {
            try? FileManager.default.removeItem(at: url)
        }
        return url
    }
}

