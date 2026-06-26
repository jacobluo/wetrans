import Foundation

public final class InMemoryCredentialStore: CredentialStore {
    public private(set) var passwords: [UUID: String] = [:]
    public private(set) var passphrases: [UUID: String] = [:]
    public private(set) var deletedHostIds: [UUID] = []

    public init() {}

    public func savePassword(_ password: String, hostId: UUID) throws {
        passwords[hostId] = password
    }

    public func loadPassword(hostId: UUID) throws -> String? {
        passwords[hostId]
    }

    public func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws {
        passphrases[hostId] = passphrase
    }

    public func loadKeyPassphrase(hostId: UUID) throws -> String? {
        passphrases[hostId]
    }

    public func deleteCredentials(hostId: UUID) throws {
        passwords.removeValue(forKey: hostId)
        passphrases.removeValue(forKey: hostId)
        deletedHostIds.append(hostId)
    }
}

