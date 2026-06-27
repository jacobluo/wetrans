import Foundation

public struct SFTPStartupOutputDiagnostic: Equatable, Sendable {
    public let detectedOutputPrefix: String

    public init?(message: String) {
        guard let length = Self.packetLengthValue(in: message),
              let prefix = Self.printablePrefix(from: length)
        else {
            return nil
        }
        self.detectedOutputPrefix = prefix
    }

    public var userMessage: String {
        """
        SFTP could not start because the remote shell printed text before the SFTP protocol began.

        Detected output prefix: "\(detectedOutputPrefix)"

        Move login/setup echo output behind an interactive-shell guard, then retry.
        Check files such as ~/.bashrc, ~/.profile, /etc/profile, or /etc/bashrc.
        """
    }

    private static func packetLengthValue(in message: String) -> UInt32? {
        guard message.localizedCaseInsensitiveContains("received message too long") else {
            return nil
        }

        let scanner = Scanner(string: message)
        while !scanner.isAtEnd {
            var value: UInt64 = 0
            if scanner.scanUnsignedLongLong(&value), value <= UInt32.max {
                return UInt32(value)
            }
            _ = scanner.scanUpToCharacters(from: .decimalDigits)
        }
        return nil
    }

    private static func printablePrefix(from length: UInt32) -> String? {
        let bytes = [
            UInt8((length >> 24) & 0xff),
            UInt8((length >> 16) & 0xff),
            UInt8((length >> 8) & 0xff),
            UInt8(length & 0xff)
        ]
        guard bytes.allSatisfy({ 0x20...0x7e ~= $0 }) else {
            return nil
        }
        return String(bytes: bytes, encoding: .ascii)
    }
}
