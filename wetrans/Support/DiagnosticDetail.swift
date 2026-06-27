import Foundation

public struct DiagnosticDetail: Equatable, Sendable {
    public let panel: String
    public let path: String
    public let message: String
    public let hostDisplayName: String?

    public init(panel: String, path: String, message: String, hostDisplayName: String?) {
        self.panel = panel
        self.path = path
        self.message = message
        self.hostDisplayName = hostDisplayName
    }

    public var report: String {
        var lines = [
            "wetrans debug detail",
            "panel: \(Self.redact(panel))",
            "path: \(Self.redact(path))",
            "message: \(Self.redact(message))"
        ]
        if let hostDisplayName, !hostDisplayName.isEmpty {
            lines.append("host: \(Self.redact(hostDisplayName))")
        }
        return lines.joined(separator: "\n")
    }

    public static func redact(_ value: String) -> String {
        var redacted = value
        redacted = redacted.replacingOccurrences(
            of: #"/Users/[^/\s]+"#,
            with: "/Users/<user>",
            options: .regularExpression
        )
        redacted = redacted.replacingOccurrences(
            of: #"(?i)\b(password|passphrase|token|authorization)(\s*[:=]?\s*)\S+"#,
            with: "$1$2<redacted>",
            options: .regularExpression
        )
        return redacted
    }
}
