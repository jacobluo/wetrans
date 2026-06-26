import Foundation

public enum HostValidationError: Error, Equatable {
    case missingDisplayName
    case missingHostname
    case invalidPort
    case missingUsername
    case missingIdentityFile
    case duplicateFavoriteRemotePath(String)
}

public enum HostValidator {
    public static func validate(_ draft: HostDraft) throws {
        try validateFields(
            displayName: draft.displayName,
            hostname: draft.hostname,
            port: draft.port,
            username: draft.username,
            authType: draft.authType,
            identityFile: draft.identityFile,
            favoriteRemotePaths: []
        )
    }

    public static func validate(_ host: SavedHost) throws {
        try validateFields(
            displayName: host.displayName,
            hostname: host.hostname,
            port: host.port,
            username: host.username,
            authType: host.authType,
            identityFile: host.identityFile,
            favoriteRemotePaths: host.favoriteRemotePaths
        )
    }

    private static func validateFields(
        displayName: String,
        hostname: String,
        port: Int,
        username: String,
        authType: AuthType,
        identityFile: String?,
        favoriteRemotePaths: [String]
    ) throws {
        guard !displayName.trimmedForValidation.isEmpty else {
            throw HostValidationError.missingDisplayName
        }
        guard !hostname.trimmedForValidation.isEmpty else {
            throw HostValidationError.missingHostname
        }
        guard (1...65_535).contains(port) else {
            throw HostValidationError.invalidPort
        }
        guard !username.trimmedForValidation.isEmpty else {
            throw HostValidationError.missingUsername
        }
        if authType == .sshKey && (identityFile?.trimmedNilIfEmpty == nil) {
            throw HostValidationError.missingIdentityFile
        }

        var seen = Set<String>()
        for path in favoriteRemotePaths.map(\.trimmedForValidation) where !path.isEmpty {
            guard seen.insert(path).inserted else {
                throw HostValidationError.duplicateFavoriteRemotePath(path)
            }
        }
    }
}

extension String {
    var trimmedForValidation: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var trimmedNilIfEmpty: String? {
        let trimmed = trimmedForValidation
        return trimmed.isEmpty ? nil : trimmed
    }
}

