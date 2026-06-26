import Foundation

public final class MockRemoteFileSystem: RemoteFileSystem {
    public struct ListCall: Equatable {
        public let path: String
        public let session: RemoteSession
    }

    public var listingsByPath: [String: [FileItem]]
    public var connectError: Error?
    public var listErrorsByPath: [String: Error]
    public private(set) var connectCalls: [ConnectionSpec] = []
    public private(set) var listCalls: [ListCall] = []
    public private(set) var disconnectedSessions: [RemoteSession] = []

    public init(listingsByPath: [String: [FileItem]] = [:], listErrorsByPath: [String: Error] = [:]) {
        self.listingsByPath = listingsByPath
        self.listErrorsByPath = listErrorsByPath
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
}

