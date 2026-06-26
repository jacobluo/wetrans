import Foundation

public protocol CredentialStore {
    func savePassword(_ password: String, hostId: UUID) throws
    func loadPassword(hostId: UUID) throws -> String?
    func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws
    func loadKeyPassphrase(hostId: UUID) throws -> String?
    func deleteCredentials(hostId: UUID) throws
}

