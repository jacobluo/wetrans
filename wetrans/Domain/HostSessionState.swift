import Foundation

public struct HostSessionState: Equatable {
    public let hostId: UUID
    public var isConnected: Bool
    public var lastActiveAt: Date?
    public var currentRemotePath: String
    public var currentLocalPath: String
    public var expandedRemotePaths: Set<String>
    public var selectedRemotePaths: Set<String>
    public var selectedLocalPaths: Set<String>
    public var remoteScrollPosition: Double?
    public var localScrollPosition: Double?

    public init(
        hostId: UUID,
        isConnected: Bool = false,
        lastActiveAt: Date? = nil,
        currentRemotePath: String,
        currentLocalPath: String,
        expandedRemotePaths: Set<String> = [],
        selectedRemotePaths: Set<String> = [],
        selectedLocalPaths: Set<String> = [],
        remoteScrollPosition: Double? = nil,
        localScrollPosition: Double? = nil
    ) {
        self.hostId = hostId
        self.isConnected = isConnected
        self.lastActiveAt = lastActiveAt
        self.currentRemotePath = currentRemotePath
        self.currentLocalPath = currentLocalPath
        self.expandedRemotePaths = expandedRemotePaths
        self.selectedRemotePaths = selectedRemotePaths
        self.selectedLocalPaths = selectedLocalPaths
        self.remoteScrollPosition = remoteScrollPosition
        self.localScrollPosition = localScrollPosition
    }
}

