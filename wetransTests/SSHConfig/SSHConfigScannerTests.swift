import XCTest
@testable import wetrans

final class SSHConfigScannerTests: XCTestCase {
    func testFiltersWildcardsAndNegatedAliases() throws {
        let text = """
        Host dev
          HostName dev.example.com

        Host prod staging
          HostName prod.example.com

        Host *
          User ubuntu

        Host prod-*
          User deploy

        Host !bad *
          User blocked
        """

        let aliases = try FileSSHConfigScanner.scanAliases(in: text)

        XCTAssertEqual(aliases.map(\.alias), ["dev", "prod", "staging"])
    }

    func testDeduplicatesAliasesPreservingFirstOccurrence() throws {
        let text = """
        Host dev
        Host prod
        Host dev
        """

        let aliases = try FileSSHConfigScanner.scanAliases(in: text)

        XCTAssertEqual(aliases.map(\.alias), ["dev", "prod"])
    }

    func testScanDefaultConfigReadsBasicIncludes() throws {
        let directory = temporaryDirectory()
        let configURL = directory.appendingPathComponent("config")
        let includeURL = directory.appendingPathComponent("team.conf")
        try """
        Host dev
          HostName dev.example.com
        Include team.conf
        """.write(to: configURL, atomically: true, encoding: .utf8)
        try """
        Host prod staging
          HostName prod.example.com
        """.write(to: includeURL, atomically: true, encoding: .utf8)

        let scanner = FileSSHConfigScanner(configURL: configURL)

        XCTAssertEqual(try scanner.scanDefaultConfig().map(\.alias), ["dev", "prod", "staging"])
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

