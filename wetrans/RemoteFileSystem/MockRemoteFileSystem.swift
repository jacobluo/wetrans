import Foundation

public final class MockRemoteFileSystem: RemoteFileSystem, @unchecked Sendable {
    public struct ListCall: Equatable {
        public let path: String
        public let session: RemoteSession
    }

    public struct UploadCall: Equatable {
        public let request: UploadRequest
        public let session: RemoteSession
    }

    public struct DownloadCall: Equatable {
        public let request: DownloadRequest
        public let session: RemoteSession
    }

    public struct EnsureDirectoryCall: Equatable {
        public let path: String
        public let session: RemoteSession
    }

    public struct CopyItemCall: Equatable {
        public let sourcePath: String
        public let destinationPath: String
        public let session: RemoteSession
    }

    public struct DeleteItemCall: Equatable {
        public let item: FileItem
        public let session: RemoteSession
    }

    public var listingsByPath: [String: [FileItem]]
    public var connectError: Error?
    public var listErrorsByPath: [String: Error]
    public var uploadProgressEvents: [TransferProgress]
    public var downloadProgressEvents: [TransferProgress]
    public var uploadError: Error?
    public var downloadError: Error?
    public var ensureDirectoryError: Error?
    public var copyItemError: Error?
    public var deleteItemError: Error?
    public private(set) var connectCalls: [ConnectionSpec] = []
    public private(set) var listCalls: [ListCall] = []
    public private(set) var ensureDirectoryCalls: [EnsureDirectoryCall] = []
    public private(set) var copyItemCalls: [CopyItemCall] = []
    public private(set) var deleteItemCalls: [DeleteItemCall] = []
    public private(set) var uploadCalls: [UploadCall] = []
    public private(set) var downloadCalls: [DownloadCall] = []
    public private(set) var disconnectedSessions: [RemoteSession] = []

    public init(
        listingsByPath: [String: [FileItem]] = [:],
        listErrorsByPath: [String: Error] = [:],
        uploadProgressEvents: [TransferProgress] = [],
        downloadProgressEvents: [TransferProgress] = []
    ) {
        self.listingsByPath = listingsByPath
        self.listErrorsByPath = listErrorsByPath
        self.uploadProgressEvents = uploadProgressEvents
        self.downloadProgressEvents = downloadProgressEvents
    }

    public func connect(_ spec: ConnectionSpec) async throws -> RemoteSession {
        if let connectError {
            throw connectError
        }
        connectCalls.append(spec)
        return RemoteSession(hostId: spec.hostId, displayName: spec.displayName)
    }

    public func disconnect(_ session: RemoteSession) async {
        disconnectedSessions.append(session)
    }

    public func listDirectory(_ path: String, in session: RemoteSession) async throws -> [FileItem] {
        listCalls.append(ListCall(path: path, session: session))
        if let error = listErrorsByPath[path] {
            throw error
        }
        return listingsByPath[path] ?? []
    }

    public func ensureDirectory(_ path: String, in session: RemoteSession) async throws {
        ensureDirectoryCalls.append(EnsureDirectoryCall(path: path, session: session))
        if let ensureDirectoryError {
            throw ensureDirectoryError
        }
    }

    public func copyItem(from sourcePath: String, to destinationPath: String, in session: RemoteSession) async throws {
        copyItemCalls.append(CopyItemCall(sourcePath: sourcePath, destinationPath: destinationPath, session: session))
        if let copyItemError {
            throw copyItemError
        }
    }

    public func deleteItem(_ item: FileItem, in session: RemoteSession) async throws {
        deleteItemCalls.append(DeleteItemCall(item: item, session: session))
        if let deleteItemError {
            throw deleteItemError
        }
    }

    public func upload(
        _ request: UploadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        uploadCalls.append(UploadCall(request: request, session: session))
        if let uploadError {
            throw uploadError
        }
        for event in uploadProgressEvents {
            await progress(event)
        }
    }

    public func download(
        _ request: DownloadRequest,
        in session: RemoteSession,
        progress: @escaping @Sendable (TransferProgress) async -> Void
    ) async throws {
        downloadCalls.append(DownloadCall(request: request, session: session))
        if let downloadError {
            throw downloadError
        }
        for event in downloadProgressEvents {
            await progress(event)
        }
    }
}
