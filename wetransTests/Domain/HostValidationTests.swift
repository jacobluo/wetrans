import XCTest
@testable import wetrans

final class HostValidationTests: XCTestCase {
    func testManualPasswordDraftWithRequiredFieldsIsValid() {
        XCTAssertNoThrow(try HostValidator.validate(HostDraft.validManualFixture()))
    }

    func testDisplayNameIsRequired() {
        var draft = HostDraft.validManualFixture()
        draft.displayName = " "

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .missingDisplayName)
        }
    }

    func testPortMustBeInRange() {
        var draft = HostDraft.validManualFixture()
        draft.port = 70_000

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .invalidPort)
        }
    }

    func testSSHKeyDraftRequiresIdentityFile() {
        var draft = HostDraft.validManualFixture()
        draft.authType = .sshKey
        draft.identityFile = nil

        XCTAssertThrowsError(try HostValidator.validate(draft)) { error in
            XCTAssertEqual(error as? HostValidationError, .missingIdentityFile)
        }
    }

    func testSavedHostRejectsDuplicateFavoritePaths() {
        var host = try! HostDraft.validManualFixture().makeSavedHost()
        host.favoriteRemotePaths = ["/var/log", "/var/log"]

        XCTAssertThrowsError(try HostValidator.validate(host)) { error in
            XCTAssertEqual(error as? HostValidationError, .duplicateFavoriteRemotePath("/var/log"))
        }
    }
}

extension HostDraft {
    static func validManualFixture() -> HostDraft {
        HostDraft(
            source: .manual,
            displayName: "dev",
            hostname: "dev.example.com",
            port: 22,
            username: "ubuntu",
            authType: .password,
            password: "secret",
            defaultRemotePath: "/home/ubuntu"
        )
    }
}

