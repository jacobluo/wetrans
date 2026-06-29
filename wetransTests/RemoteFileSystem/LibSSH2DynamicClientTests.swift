import XCTest
@testable import wetrans

final class LibSSH2DynamicClientTests: XCTestCase {
    func testJoinBuildsRemoteChildPaths() {
        XCTAssertEqual(LibSSH2Path.join(directory: "/var/log", name: "app.log"), "/var/log/app.log")
        XCTAssertEqual(LibSSH2Path.join(directory: "/", name: "etc"), "/etc")
        XCTAssertEqual(LibSSH2Path.join(directory: "relative", name: "file"), "relative/file")
    }

    func testPermissionsTextUsesUnixStyleFileTypeAndModeBits() {
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o040755), "drwxr-xr-x")
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o100644), "-rw-r--r--")
        XCTAssertEqual(LibSSH2Path.permissionsText(from: 0o120777), "lrwxrwxrwx")
    }

    func testFileTypeHelpersUseModeBits() {
        XCTAssertTrue(LibSSH2Path.isDirectory(permissions: 0o040755))
        XCTAssertFalse(LibSSH2Path.isDirectory(permissions: 0o100644))
        XCTAssertTrue(LibSSH2Path.isSymlink(permissions: 0o120777))
        XCTAssertFalse(LibSSH2Path.isSymlink(permissions: 0o100644))
    }

    func testTransferOpenModesUseSFTPFileConstants() {
        XCTAssertEqual(LibSSH2TransferOpenMode.uploadFlags, 0x0000_0002 | 0x0000_0008 | 0x0000_0010)
        XCTAssertEqual(LibSSH2TransferOpenMode.downloadFlags, 0x0000_0001)
        XCTAssertEqual(LibSSH2TransferOpenMode.fileMode, 0o100644)
        XCTAssertEqual(LibSSH2TransferOpenMode.openFileType, 0)
    }

    func testDirectoryOpenModeUsesSFTPOpenDirectoryConstant() {
        XCTAssertEqual(LibSSH2DirectoryOpenMode.openDirectory, 1)
    }

    func testLibSSH2ErrorMessageKeepsOperationContextWhenLibraryProvidesGenericMessage() {
        let message = LibSSH2ErrorContext.message(
            fallback: "Unable to write remote file /remote/滴滴出行行程报销单.pdf",
            libraryMessage: "SFTP Protocol Error",
            code: -31,
            sftpStatus: nil
        )

        XCTAssertEqual(
            message,
            "Unable to write remote file /remote/滴滴出行行程报销单.pdf: SFTP Protocol Error"
        )
    }

    func testLibSSH2ErrorMessageIncludesSFTPStatusWhenAvailable() {
        let message = LibSSH2ErrorContext.message(
            fallback: "Unable to write remote file /remote/滴滴出行行程报销单.pdf",
            libraryMessage: "SFTP Protocol Error",
            code: -31,
            sftpStatus: 4
        )

        XCTAssertEqual(
            message,
            "Unable to write remote file /remote/滴滴出行行程报销单.pdf: SFTP Protocol Error (SFTP status 4: failure)"
        )
    }

    func testDirectoryCreationPolicyTreatsGenericFailureAsSuccessOnlyWhenDirectoryNowExists() {
        XCTAssertTrue(
            LibSSH2DirectoryCreationPolicy.shouldContinueAfterMkdirFailure(
                sftpStatus: 4,
                directoryExistsAfterFailure: { true }
            )
        )
        XCTAssertFalse(
            LibSSH2DirectoryCreationPolicy.shouldContinueAfterMkdirFailure(
                sftpStatus: 4,
                directoryExistsAfterFailure: { false }
            )
        )
    }

    func testDirectoryCreationPolicyHandlesExplicitSFTPStatusesWithoutDirectoryLookup() {
        var didCheckDirectory = false

        XCTAssertTrue(
            LibSSH2DirectoryCreationPolicy.shouldContinueAfterMkdirFailure(
                sftpStatus: 11,
                directoryExistsAfterFailure: {
                    didCheckDirectory = true
                    return false
                }
            )
        )
        XCTAssertFalse(didCheckDirectory)

        XCTAssertFalse(
            LibSSH2DirectoryCreationPolicy.shouldContinueAfterMkdirFailure(
                sftpStatus: 3,
                directoryExistsAfterFailure: {
                    didCheckDirectory = true
                    return true
                }
            )
        )
        XCTAssertFalse(didCheckDirectory)
    }

    func testPublicKeyAuthUsesPrivateKeyWithoutSeparatePublicKeyFile() {
        let files = LibSSH2PublicKeyAuthFiles(identityFile: "/Users/me/.ssh/id_ed25519")

        XCTAssertNil(files.publicKeyFile)
        XCTAssertEqual(files.privateKeyFile, "/Users/me/.ssh/id_ed25519")
    }

    func testPublicKeyAuthExpandsTildePrivateKeyPath() {
        let files = LibSSH2PublicKeyAuthFiles(identityFile: "~/.ssh/id_ed25519")

        XCTAssertNil(files.publicKeyFile)
        XCTAssertEqual(files.privateKeyFile, "\(NSHomeDirectory())/.ssh/id_ed25519")
    }
}
