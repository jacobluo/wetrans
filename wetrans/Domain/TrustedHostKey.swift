import Foundation

public struct TrustedHostKey: Identifiable, Codable, Equatable, Sendable {
    public let id: UUID
    public let hostId: UUID
    public var hostname: String
    public var port: Int
    public var keyType: String
    public var fingerprintSHA256: String
    public var firstTrustedAt: Date
    public var lastVerifiedAt: Date

    public init(
        id: UUID = UUID(),
        hostId: UUID,
        hostname: String,
        port: Int,
        keyType: String,
        fingerprintSHA256: String,
        firstTrustedAt: Date,
        lastVerifiedAt: Date
    ) {
        self.id = id
        self.hostId = hostId
        self.hostname = hostname
        self.port = port
        self.keyType = keyType
        self.fingerprintSHA256 = fingerprintSHA256
        self.firstTrustedAt = firstTrustedAt
        self.lastVerifiedAt = lastVerifiedAt
    }
}
