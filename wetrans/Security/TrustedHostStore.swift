import Foundation

public protocol TrustedHostStore {
    func lookup(hostId: UUID, hostname: String, port: Int) throws -> TrustedHostKey?
    func trust(_ key: TrustedHostKey) throws
    func recordVerification(hostId: UUID, hostname: String, port: Int, at date: Date) throws
    func deleteKeys(hostId: UUID) throws
}

