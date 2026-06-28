import CryptoKit
import Darwin
import Foundation

public final class LibSSH2DynamicClient: LibSSH2Client {
    private let runtime: LibSSH2RuntimeManaging
    private var symbols: LibSSH2Symbols?
    private var socketFD: Int32 = -1
    private var session: OpaquePointer?
    private var sftp: OpaquePointer?

    public init(runtime: LibSSH2RuntimeManaging = LibSSH2Runtime()) {
        self.runtime = runtime
    }

    public func connect(_ spec: ConnectionSpec) throws {
        let provider = try runtime.symbolProvider()
        let symbols = try LibSSH2Symbols(provider: provider)
        self.symbols = symbols

        socketFD = try Self.openSocket(hostname: spec.hostname, port: spec.port)
        guard let session = symbols.sessionInitEx(nil, nil, nil, nil) else {
            throw RemoteFileSystemError.connectionFailed("Unable to create SSH session")
        }
        self.session = session

        symbols.sessionSetBlocking(session, 1)
        let handshakeStatus = symbols.sessionHandshake(session, socketFD)
        guard handshakeStatus == 0 else {
            throw RemoteFileSystemError.connectionFailed(lastErrorMessage(fallback: "SSH handshake failed"))
        }
    }

    public func hostKey(hostId: UUID, hostname: String, port: Int, at date: Date) throws -> TrustedHostKey {
        guard let symbols, let session else {
            throw RemoteFileSystemError.disconnected
        }

        var length = 0
        var type: Int32 = 0
        guard let pointer = symbols.hostKey(session, &length, &type), length > 0 else {
            throw RemoteFileSystemError.connectionFailed(lastErrorMessage(fallback: "Unable to read host key"))
        }

        let data = Data(bytes: pointer, count: length)
        let digest = SHA256.hash(data: data)
        let fingerprint = Data(digest).base64EncodedString().replacingOccurrences(of: "=", with: "")

        return TrustedHostKey(
            hostId: hostId,
            hostname: hostname,
            port: port,
            keyType: Self.hostKeyTypeName(type),
            fingerprintSHA256: "SHA256:\(fingerprint)",
            firstTrustedAt: date,
            lastVerifiedAt: date
        )
    }

    public func authenticate(username: String, auth: ConnectionAuth) throws {
        guard let symbols, let session else {
            throw RemoteFileSystemError.disconnected
        }

        let status: Int32
        switch auth {
        case .password(let password):
            status = username.withCString { usernamePointer in
                (password ?? "").withCString { passwordPointer in
                    symbols.userauthPasswordEx(
                        session,
                        usernamePointer,
                        UInt32(strlen(usernamePointer)),
                        passwordPointer,
                        UInt32(strlen(passwordPointer)),
                        nil
                    )
                }
            }
        case .sshKey(let identityFile, let passphrase):
            let authFiles = LibSSH2PublicKeyAuthFiles(identityFile: identityFile)
            status = username.withCString { usernamePointer in
                authFiles.privateKeyFile.withCString { privateKeyPointer in
                    (passphrase ?? "").withCString { passphrasePointer in
                        if let publicKeyFile = authFiles.publicKeyFile {
                            return publicKeyFile.withCString { publicKeyPointer in
                                symbols.userauthPublicKeyFromFileEx(
                                    session,
                                    usernamePointer,
                                    UInt32(strlen(usernamePointer)),
                                    publicKeyPointer,
                                    privateKeyPointer,
                                    passphrasePointer
                                )
                            }
                        }
                        return symbols.userauthPublicKeyFromFileEx(
                            session,
                            usernamePointer,
                            UInt32(strlen(usernamePointer)),
                            nil,
                            privateKeyPointer,
                            passphrasePointer
                        )
                    }
                }
            }
        }

        guard status == 0 else {
            throw RemoteFileSystemError.connectionFailed(lastErrorMessage(fallback: "SSH authentication failed"))
        }
    }

    public func openSFTP() throws {
        guard let symbols, let session else {
            throw RemoteFileSystemError.disconnected
        }

        guard let sftp = symbols.sftpInit(session) else {
            throw RemoteFileSystemError.connectionFailed(lastErrorMessage(fallback: "Unable to open SFTP session"))
        }
        self.sftp = sftp
    }

    public func probeStartupOutput(
        command: String,
        timeout: TimeInterval,
        outputLimit: Int
    ) throws -> SSHStartupOutputProbeResult {
        throw RemoteFileSystemError.connectionFailed("SSH startup output probe is not implemented")
    }

    public func listDirectory(_ path: String) throws -> [FileItem] {
        guard let symbols, let sftp else {
            throw RemoteFileSystemError.disconnected
        }

        let handle = path.withCString { pathPointer in
            symbols.sftpOpenEx(sftp, pathPointer, UInt32(strlen(pathPointer)), 0, 0, LibSSH2DirectoryOpenMode.openDirectory)
        }
        guard let handle else {
            throw mapSFTPPathOpenError(path: path)
        }
        defer {
            _ = symbols.sftpCloseHandle(handle)
        }

        var items: [FileItem] = []
        var buffer = [CChar](repeating: 0, count: 4096)
        var longEntry = [CChar](repeating: 0, count: 8192)

        while true {
            var attributes = LibSSH2SFTPAttributes()
            let count = withUnsafeMutablePointer(to: &attributes) { attributesPointer in
                symbols.sftpReadDirEx(
                    handle,
                    &buffer,
                    buffer.count,
                    &longEntry,
                    longEntry.count,
                    UnsafeMutableRawPointer(attributesPointer)
                )
            }

            if count == 0 {
                break
            }
            guard count > 0 else {
                throw RemoteFileSystemError.connectionFailed(lastErrorMessage(fallback: "Unable to read SFTP directory"))
            }

            let name = String(decoding: buffer.prefix(count).map { UInt8(bitPattern: $0) }, as: UTF8.self)
            guard name != ".", name != ".." else {
                continue
            }

            let permissions = attributes.hasPermissions ? attributes.permissions : nil
            let modifiedAt = attributes.hasModifiedTime ? Date(timeIntervalSince1970: TimeInterval(attributes.mtime)) : nil
            items.append(
                FileItem(
                    name: name,
                    path: LibSSH2Path.join(directory: path, name: name),
                    isDirectory: permissions.map(LibSSH2Path.isDirectory) ?? false,
                    isSymlink: permissions.map(LibSSH2Path.isSymlink) ?? false,
                    size: attributes.hasSize ? attributes.filesize : nil,
                    modifiedAt: modifiedAt,
                    permissions: permissions.map(LibSSH2Path.permissionsText)
                )
            )
        }

        return items
    }

    public func ensureDirectory(_ path: String) throws {
        guard let symbols, let sftp else {
            throw RemoteFileSystemError.disconnected
        }

        for directory in Self.directoryPrefixes(for: path) {
            do {
                _ = try listDirectory(directory)
                continue
            } catch RemoteFileSystemError.notDirectory {
                let status = directory.withCString { pathPointer in
                    symbols.sftpMkdirEx(
                        sftp,
                        pathPointer,
                        UInt32(strlen(pathPointer)),
                        LibSSH2TransferOpenMode.directoryMode
                    )
                }
                guard status == 0 else {
                    switch symbols.sftpLastError(sftp) {
                    case LibSSH2Constants.sftpFileAlreadyExists:
                        continue
                    case LibSSH2Constants.sftpPermissionDenied:
                        throw RemoteFileSystemError.permissionDenied(directory)
                    default:
                        throw RemoteFileSystemError.connectionFailed(
                            lastErrorMessage(
                                fallback: "Unable to create remote directory \(directory)",
                                sftpStatus: symbols.sftpLastError(sftp)
                            )
                        )
                    }
                }
            }
        }
    }

    public func upload(
        _ request: UploadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        guard let symbols, let sftp else {
            throw RemoteFileSystemError.disconnected
        }

        let localURL = URL(fileURLWithPath: request.localPath)
        let attributes = try FileManager.default.attributesOfItem(atPath: localURL.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular else {
            throw RemoteFileSystemError.connectionFailed("Local path is not a regular file: \(request.localPath)")
        }
        let totalBytes = (attributes[.size] as? NSNumber)?.uint64Value
        let localHandle = try FileHandle(forReadingFrom: localURL)
        defer {
            try? localHandle.close()
        }

        let remoteHandle = request.remotePath.withCString { pathPointer in
            symbols.sftpOpenEx(
                sftp,
                pathPointer,
                UInt32(strlen(pathPointer)),
                LibSSH2TransferOpenMode.uploadFlags,
                LibSSH2TransferOpenMode.fileMode,
                LibSSH2TransferOpenMode.openFileType
            )
        }
        guard let remoteHandle else {
            throw mapSFTPFileOpenError(path: request.remotePath, operation: "open remote file for upload")
        }
        defer {
            _ = symbols.sftpCloseHandle(remoteHandle)
        }

        let startedAt = Date()
        var transferredBytes: UInt64 = 0
        while true {
            try Task.checkCancellation()
            let data = try localHandle.read(upToCount: LibSSH2TransferOpenMode.chunkSize) ?? Data()
            if data.isEmpty {
                break
            }

            try data.withUnsafeBytes { rawBuffer in
                guard let baseAddress = rawBuffer.baseAddress else {
                    return
                }
                var writtenTotal = 0
                while writtenTotal < data.count {
                    let pointer = baseAddress
                        .advanced(by: writtenTotal)
                        .assumingMemoryBound(to: CChar.self)
                    let written = symbols.sftpWrite(remoteHandle, pointer, data.count - writtenTotal)
                    guard written > 0 else {
                        throw RemoteFileSystemError.connectionFailed(
                            lastErrorMessage(
                                fallback: "Unable to write remote file \(request.remotePath)",
                                sftpStatus: symbols.sftpLastError(sftp)
                            )
                        )
                    }
                    writtenTotal += written
                }
            }

            transferredBytes += UInt64(data.count)
            await progress(
                TransferProgress(
                    transferredBytes: transferredBytes,
                    totalBytes: totalBytes,
                    speedBytesPerSecond: Self.speed(transferredBytes: transferredBytes, startedAt: startedAt)
                )
            )
        }
    }

    public func download(
        _ request: DownloadRequest,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        guard let symbols, let sftp else {
            throw RemoteFileSystemError.disconnected
        }

        let remoteHandle = request.remotePath.withCString { pathPointer in
            symbols.sftpOpenEx(
                sftp,
                pathPointer,
                UInt32(strlen(pathPointer)),
                LibSSH2TransferOpenMode.downloadFlags,
                0,
                LibSSH2TransferOpenMode.openFileType
            )
        }
        guard let remoteHandle else {
            throw mapSFTPFileOpenError(path: request.remotePath, operation: "open remote file for download")
        }
        defer {
            _ = symbols.sftpCloseHandle(remoteHandle)
        }

        let localURL = URL(fileURLWithPath: request.localPath)
        try FileManager.default.createDirectory(
            at: localURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: localURL.path, contents: nil) else {
            throw RemoteFileSystemError.connectionFailed("Unable to create local file: \(request.localPath)")
        }
        let localHandle = try FileHandle(forWritingTo: localURL)
        defer {
            try? localHandle.close()
        }

        let startedAt = Date()
        var transferredBytes: UInt64 = 0
        var buffer = [CChar](repeating: 0, count: LibSSH2TransferOpenMode.chunkSize)
        while true {
            try Task.checkCancellation()
            let count = symbols.sftpRead(remoteHandle, &buffer, buffer.count)
            if count == 0 {
                break
            }
            guard count > 0 else {
                throw RemoteFileSystemError.connectionFailed(
                    lastErrorMessage(
                        fallback: "Unable to read remote file \(request.remotePath)",
                        sftpStatus: symbols.sftpLastError(sftp)
                    )
                )
            }

            let data = Data(buffer.prefix(count).map { UInt8(bitPattern: $0) })
            try localHandle.write(contentsOf: data)
            transferredBytes += UInt64(count)
            await progress(
                TransferProgress(
                    transferredBytes: transferredBytes,
                    totalBytes: nil,
                    speedBytesPerSecond: Self.speed(transferredBytes: transferredBytes, startedAt: startedAt)
                )
            )
        }
    }

    public func disconnect() {
        if let symbols {
            if let sftp {
                _ = symbols.sftpShutdown(sftp)
                self.sftp = nil
            }
            if let session {
                _ = symbols.sessionDisconnectEx(session, 11, "wetrans disconnect", "")
                _ = symbols.sessionFree(session)
                self.session = nil
            }
        }

        if socketFD >= 0 {
            close(socketFD)
            socketFD = -1
        }
    }

    private func lastErrorMessage(fallback: String, sftpStatus: UInt64? = nil) -> String {
        guard let symbols, let session else {
            return fallback
        }

        var messagePointer: UnsafeMutablePointer<CChar>?
        var messageLength: Int32 = 0
        let code = symbols.sessionLastError(session, &messagePointer, &messageLength, 0)
        guard let messagePointer, messageLength > 0 else {
            return LibSSH2ErrorContext.message(
                fallback: fallback,
                libraryMessage: nil,
                code: code,
                sftpStatus: sftpStatus
            )
        }
        let data = Data(bytes: messagePointer, count: Int(messageLength))
        return LibSSH2ErrorContext.message(
            fallback: fallback,
            libraryMessage: String(data: data, encoding: .utf8),
            code: code,
            sftpStatus: sftpStatus
        )
    }

    private func mapSFTPPathOpenError(path: String) -> Error {
        guard let symbols, let sftp else {
            return RemoteFileSystemError.disconnected
        }

        switch symbols.sftpLastError(sftp) {
        case LibSSH2Constants.sftpPermissionDenied:
            return RemoteFileSystemError.permissionDenied(path)
        case LibSSH2Constants.sftpNoSuchFile, LibSSH2Constants.sftpFailure:
            return RemoteFileSystemError.notDirectory(path)
        default:
            return RemoteFileSystemError.connectionFailed(
                lastErrorMessage(fallback: "Unable to open SFTP directory \(path)", sftpStatus: symbols.sftpLastError(sftp))
            )
        }
    }

    private func mapSFTPFileOpenError(path: String, operation: String) -> Error {
        guard let symbols, let sftp else {
            return RemoteFileSystemError.disconnected
        }

        switch symbols.sftpLastError(sftp) {
        case LibSSH2Constants.sftpPermissionDenied:
            return RemoteFileSystemError.permissionDenied(path)
        default:
            return RemoteFileSystemError.connectionFailed(
                lastErrorMessage(fallback: "Unable to \(operation): \(path)", sftpStatus: symbols.sftpLastError(sftp))
            )
        }
    }

    private static func speed(transferredBytes: UInt64, startedAt: Date) -> UInt64? {
        let elapsed = Date().timeIntervalSince(startedAt)
        guard elapsed > 0 else {
            return nil
        }
        return UInt64(Double(transferredBytes) / elapsed)
    }

    private static func directoryPrefixes(for path: String) -> [String] {
        let trimmed = path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !trimmed.isEmpty, path != "." else {
            return []
        }

        let parts = trimmed.split(separator: "/").map(String.init)
        var prefixes: [String] = []
        for index in parts.indices {
            let prefix = parts[...index].joined(separator: "/")
            prefixes.append(path.hasPrefix("/") ? "/\(prefix)" : prefix)
        }
        return prefixes
    }

    private static func hostKeyTypeName(_ type: Int32) -> String {
        switch type {
        case 1:
            return "ssh-rsa"
        case 2:
            return "ssh-dss"
        case 3:
            return "ecdsa-sha2-nistp256"
        case 4:
            return "ecdsa-sha2-nistp384"
        case 5:
            return "ecdsa-sha2-nistp521"
        case 6:
            return "ssh-ed25519"
        default:
            return "unknown"
        }
    }

    private static func openSocket(hostname: String, port: Int) throws -> Int32 {
        var hints = addrinfo(
            ai_flags: 0,
            ai_family: AF_UNSPEC,
            ai_socktype: SOCK_STREAM,
            ai_protocol: IPPROTO_TCP,
            ai_addrlen: 0,
            ai_canonname: nil,
            ai_addr: nil,
            ai_next: nil
        )
        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(hostname, String(port), &hints, &result)
        guard status == 0, let result else {
            throw RemoteFileSystemError.connectionFailed(String(cString: gai_strerror(status)))
        }
        defer {
            freeaddrinfo(result)
        }

        var cursor: UnsafeMutablePointer<addrinfo>? = result
        var lastErrno = errno
        while let current = cursor {
            let fd = socket(current.pointee.ai_family, current.pointee.ai_socktype, current.pointee.ai_protocol)
            if fd >= 0 {
                if Darwin.connect(fd, current.pointee.ai_addr, current.pointee.ai_addrlen) == 0 {
                    return fd
                }
                lastErrno = errno
                close(fd)
            } else {
                lastErrno = errno
            }
            cursor = current.pointee.ai_next
        }

        throw RemoteFileSystemError.connectionFailed(String(cString: strerror(lastErrno)))
    }
}

struct LibSSH2PublicKeyAuthFiles: Equatable {
    let publicKeyFile: String?
    let privateKeyFile: String

    init(identityFile: String) {
        self.publicKeyFile = nil
        self.privateKeyFile = (identityFile as NSString).expandingTildeInPath
    }
}

public enum LibSSH2ErrorContext {
    public static func message(
        fallback: String,
        libraryMessage: String?,
        code: Int32,
        sftpStatus: UInt64? = nil
    ) -> String {
        let suffix = sftpStatus.flatMap(Self.sftpStatusSuffix) ?? ""
        guard let libraryMessage = libraryMessage?.trimmingCharacters(in: .whitespacesAndNewlines),
              !libraryMessage.isEmpty
        else {
            return "\(fallback) (libssh2 error \(code))\(suffix)"
        }
        guard libraryMessage != fallback else {
            return "\(fallback)\(suffix)"
        }
        return "\(fallback): \(libraryMessage)\(suffix)"
    }

    private static func sftpStatusSuffix(_ status: UInt64) -> String? {
        guard status > 0 else {
            return nil
        }
        return " (SFTP status \(status): \(sftpStatusName(status)))"
    }

    private static func sftpStatusName(_ status: UInt64) -> String {
        switch status {
        case LibSSH2Constants.sftpNoSuchFile:
            return "no such file"
        case LibSSH2Constants.sftpPermissionDenied:
            return "permission denied"
        case LibSSH2Constants.sftpFailure:
            return "failure"
        case LibSSH2Constants.sftpFileAlreadyExists:
            return "file already exists"
        default:
            return "unknown"
        }
    }
}

private struct LibSSH2Constants {
    static let sftpNoSuchFile: UInt64 = 2
    static let sftpPermissionDenied: UInt64 = 3
    static let sftpFailure: UInt64 = 4
    static let sftpFileAlreadyExists: UInt64 = 11
    static let attrSize: UInt64 = 0x0000_0001
    static let attrPermissions: UInt64 = 0x0000_0004
    static let attrAccessModifyTime: UInt64 = 0x0000_0008
}

enum LibSSH2DirectoryOpenMode {
    static let openDirectory: Int32 = 1
}

public enum LibSSH2TransferOpenMode {
    public static let downloadFlags: UInt64 = 0x0000_0001
    public static let uploadFlags: UInt64 = 0x0000_0002 | 0x0000_0008 | 0x0000_0010
    public static let fileMode: Int64 = 0o100644
    public static let directoryMode: Int64 = 0o040755
    public static let openFileType: Int32 = 0
    public static let chunkSize = 32 * 1024
}

private struct LibSSH2SFTPAttributes {
    var flags: UInt64 = 0
    var filesize: UInt64 = 0
    var uid: UInt64 = 0
    var gid: UInt64 = 0
    var permissions: UInt64 = 0
    var atime: UInt64 = 0
    var mtime: UInt64 = 0

    var hasSize: Bool {
        flags & LibSSH2Constants.attrSize == LibSSH2Constants.attrSize
    }

    var hasPermissions: Bool {
        flags & LibSSH2Constants.attrPermissions == LibSSH2Constants.attrPermissions
    }

    var hasModifiedTime: Bool {
        flags & LibSSH2Constants.attrAccessModifyTime == LibSSH2Constants.attrAccessModifyTime
    }
}

private struct LibSSH2Symbols {
    typealias SessionInitEx = @convention(c) (
        UnsafeRawPointer?,
        UnsafeRawPointer?,
        UnsafeRawPointer?,
        UnsafeRawPointer?
    ) -> OpaquePointer?
    typealias SessionSetBlocking = @convention(c) (OpaquePointer, Int32) -> Void
    typealias SessionHandshake = @convention(c) (OpaquePointer, Int32) -> Int32
    typealias HostKey = @convention(c) (
        OpaquePointer,
        UnsafeMutablePointer<Int>?,
        UnsafeMutablePointer<Int32>?
    ) -> UnsafePointer<CChar>?
    typealias UserAuthPasswordEx = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UInt32,
        UnsafePointer<CChar>,
        UInt32,
        UnsafeRawPointer?
    ) -> Int32
    typealias UserAuthPublicKeyFromFileEx = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UInt32,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>,
        UnsafePointer<CChar>?
    ) -> Int32
    typealias SessionLastError = @convention(c) (
        OpaquePointer,
        UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>?,
        UnsafeMutablePointer<Int32>?,
        Int32
    ) -> Int32
    typealias SFTPInit = @convention(c) (OpaquePointer) -> OpaquePointer?
    typealias SFTPOpenEx = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UInt32,
        UInt64,
        Int64,
        Int32
    ) -> OpaquePointer?
    typealias SFTPReadDirEx = @convention(c) (
        OpaquePointer,
        UnsafeMutablePointer<CChar>,
        Int,
        UnsafeMutablePointer<CChar>,
        Int,
        UnsafeMutableRawPointer?
    ) -> Int
    typealias SFTPCloseHandle = @convention(c) (OpaquePointer) -> Int32
    typealias SFTPRead = @convention(c) (
        OpaquePointer,
        UnsafeMutablePointer<CChar>,
        Int
    ) -> Int
    typealias SFTPWrite = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        Int
    ) -> Int
    typealias SFTPShutdown = @convention(c) (OpaquePointer) -> Int32
    typealias SFTPLastError = @convention(c) (OpaquePointer) -> UInt64
    typealias SFTPMkdirEx = @convention(c) (
        OpaquePointer,
        UnsafePointer<CChar>,
        UInt32,
        Int64
    ) -> Int32
    typealias SessionDisconnectEx = @convention(c) (
        OpaquePointer,
        Int32,
        UnsafePointer<CChar>?,
        UnsafePointer<CChar>?
    ) -> Int32
    typealias SessionFree = @convention(c) (OpaquePointer) -> Int32

    let sessionInitEx: SessionInitEx
    let sessionSetBlocking: SessionSetBlocking
    let sessionHandshake: SessionHandshake
    let hostKey: HostKey
    let userauthPasswordEx: UserAuthPasswordEx
    let userauthPublicKeyFromFileEx: UserAuthPublicKeyFromFileEx
    let sessionLastError: SessionLastError
    let sftpInit: SFTPInit
    let sftpOpenEx: SFTPOpenEx
    let sftpReadDirEx: SFTPReadDirEx
    let sftpCloseHandle: SFTPCloseHandle
    let sftpRead: SFTPRead
    let sftpWrite: SFTPWrite
    let sftpShutdown: SFTPShutdown
    let sftpLastError: SFTPLastError
    let sftpMkdirEx: SFTPMkdirEx
    let sessionDisconnectEx: SessionDisconnectEx
    let sessionFree: SessionFree

    init(provider: LibSSH2SymbolProviding) throws {
        sessionInitEx = try Self.load("libssh2_session_init_ex", from: provider, as: SessionInitEx.self)
        sessionSetBlocking = try Self.load("libssh2_session_set_blocking", from: provider, as: SessionSetBlocking.self)
        sessionHandshake = try Self.load("libssh2_session_handshake", from: provider, as: SessionHandshake.self)
        hostKey = try Self.load("libssh2_session_hostkey", from: provider, as: HostKey.self)
        userauthPasswordEx = try Self.load("libssh2_userauth_password_ex", from: provider, as: UserAuthPasswordEx.self)
        userauthPublicKeyFromFileEx = try Self.load(
            "libssh2_userauth_publickey_fromfile_ex",
            from: provider,
            as: UserAuthPublicKeyFromFileEx.self
        )
        sessionLastError = try Self.load("libssh2_session_last_error", from: provider, as: SessionLastError.self)
        sftpInit = try Self.load("libssh2_sftp_init", from: provider, as: SFTPInit.self)
        sftpOpenEx = try Self.load("libssh2_sftp_open_ex", from: provider, as: SFTPOpenEx.self)
        sftpReadDirEx = try Self.load("libssh2_sftp_readdir_ex", from: provider, as: SFTPReadDirEx.self)
        sftpCloseHandle = try Self.load("libssh2_sftp_close_handle", from: provider, as: SFTPCloseHandle.self)
        sftpRead = try Self.load("libssh2_sftp_read", from: provider, as: SFTPRead.self)
        sftpWrite = try Self.load("libssh2_sftp_write", from: provider, as: SFTPWrite.self)
        sftpShutdown = try Self.load("libssh2_sftp_shutdown", from: provider, as: SFTPShutdown.self)
        sftpLastError = try Self.load("libssh2_sftp_last_error", from: provider, as: SFTPLastError.self)
        sftpMkdirEx = try Self.load("libssh2_sftp_mkdir_ex", from: provider, as: SFTPMkdirEx.self)
        sessionDisconnectEx = try Self.load("libssh2_session_disconnect_ex", from: provider, as: SessionDisconnectEx.self)
        sessionFree = try Self.load("libssh2_session_free", from: provider, as: SessionFree.self)
    }

    private static func load<T>(_ name: String, from provider: LibSSH2SymbolProviding, as type: T.Type) throws -> T {
        guard let symbol = provider.symbol(named: name) else {
            throw LibSSH2Error.missingSymbol(name)
        }
        return unsafeBitCast(symbol, to: type)
    }
}
