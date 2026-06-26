import Foundation
import Security

public final class KeychainCredentialStore: CredentialStore {
    private let passwordService: String
    private let keyPassphraseService: String

    public init(
        passwordService: String = "wetrans.ssh.password",
        keyPassphraseService: String = "wetrans.ssh.keyPassphrase"
    ) {
        self.passwordService = passwordService
        self.keyPassphraseService = keyPassphraseService
    }

    public func savePassword(_ password: String, hostId: UUID) throws {
        try save(password, service: passwordService, hostId: hostId, operation: "savePassword")
    }

    public func loadPassword(hostId: UUID) throws -> String? {
        try load(service: passwordService, hostId: hostId, operation: "loadPassword")
    }

    public func saveKeyPassphrase(_ passphrase: String, hostId: UUID) throws {
        try save(passphrase, service: keyPassphraseService, hostId: hostId, operation: "saveKeyPassphrase")
    }

    public func loadKeyPassphrase(hostId: UUID) throws -> String? {
        try load(service: keyPassphraseService, hostId: hostId, operation: "loadKeyPassphrase")
    }

    public func deleteCredentials(hostId: UUID) throws {
        try delete(service: passwordService, hostId: hostId, operation: "deletePassword")
        try delete(service: keyPassphraseService, hostId: hostId, operation: "deleteKeyPassphrase")
    }

    private func save(_ value: String, service: String, hostId: UUID, operation: String) throws {
        let data = Data(value.utf8)
        let query = baseQuery(service: service, hostId: hostId)
        let attributes: [String: Any] = [kSecValueData as String: data]

        let updateStatus = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if updateStatus == errSecSuccess {
            return
        }
        if updateStatus != errSecItemNotFound {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: updateStatus)
        }

        var addQuery = query
        addQuery[kSecValueData as String] = data
        let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
        guard addStatus == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: addStatus)
        }
    }

    private func load(service: String, hostId: UUID, operation: String) throws -> String? {
        var query = baseQuery(service: service, hostId: hostId)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        if status == errSecItemNotFound {
            return nil
        }
        guard status == errSecSuccess else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: status)
        }
        guard let data = item as? Data, let value = String(data: data, encoding: .utf8) else {
            throw CredentialStoreError.invalidStoredData
        }
        return value
    }

    private func delete(service: String, hostId: UUID, operation: String) throws {
        let status = SecItemDelete(baseQuery(service: service, hostId: hostId) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw CredentialStoreError.unexpectedStatus(operation: operation, status: status)
        }
    }

    private func baseQuery(service: String, hostId: UUID) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: hostId.uuidString
        ]
    }
}

