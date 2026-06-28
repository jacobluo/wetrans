import Foundation

public enum SSHStartupOutputProbeEvidence: Equatable, Sendable {
    case strong
    case weak
    case none
}

public struct SSHStartupOutputProbeResult: Equatable, Sendable {
    public let stdoutPreview: String
    public let stderrPreview: String
    public let stdoutTruncated: Bool
    public let stderrTruncated: Bool

    public init(stdout: Data, stderr: Data, outputLimit: Int = 4096) {
        let stdoutPreview = Self.preview(stdout, limit: outputLimit)
        let stderrPreview = Self.preview(stderr, limit: outputLimit)
        self.stdoutPreview = stdoutPreview.text
        self.stderrPreview = stderrPreview.text
        self.stdoutTruncated = stdoutPreview.truncated
        self.stderrTruncated = stderrPreview.truncated
    }

    public var evidence: SSHStartupOutputProbeEvidence {
        if !stdoutPreview.isEmpty {
            return .strong
        }
        if !stderrPreview.isEmpty {
            return .weak
        }
        return .none
    }

    public static func shouldProbe(afterConnectionFailure message: String) -> Bool {
        let normalized = message.lowercased()
        return normalized.contains("unable to open sftp session")
            || normalized.contains("timeout waiting for response from sftp subsystem")
            || SFTPStartupOutputDiagnostic(message: message) != nil
    }

    public func diagnosticMessage(originalError: String) -> String? {
        switch evidence {
        case .strong:
            return """
            SFTP could not start because the remote shell printed text during a non-interactive SSH session.

            Detected output:
            \(stdoutPreview)

            Move login/setup output behind an interactive-shell guard, then retry.
            Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
            """
        case .weak:
            return """
            SFTP could not start. The remote SSH startup produced diagnostics while checking for non-interactive output.

            Original SFTP error: \(originalError)

            Remote stderr:
            \(stderrPreview)

            If SFTP still fails, inspect shell startup files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
            """
        case .none:
            return nil
        }
    }

    private static func preview(_ data: Data, limit: Int) -> (text: String, truncated: Bool) {
        let boundedLimit = max(0, limit)
        let prefix = data.prefix(boundedLimit)
        return (String(decoding: prefix, as: UTF8.self), data.count > boundedLimit)
    }
}
