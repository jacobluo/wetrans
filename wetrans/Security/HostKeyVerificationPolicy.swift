import Foundation

public enum HostKeyVerificationDecision: Equatable {
    case trusted(TrustedHostKey)
    case requiresTrust(candidate: TrustedHostKey)
    case blockedChangedKey(expected: TrustedHostKey, actual: TrustedHostKey)
}

public enum HostKeyVerificationPolicy {
    public static func decide(
        trusted: TrustedHostKey?,
        candidate: TrustedHostKey
    ) -> HostKeyVerificationDecision {
        guard let trusted else {
            return .requiresTrust(candidate: candidate)
        }
        guard trusted.keyType == candidate.keyType,
              trusted.fingerprintSHA256 == candidate.fingerprintSHA256 else {
            return .blockedChangedKey(expected: trusted, actual: candidate)
        }
        return .trusted(trusted)
    }
}

