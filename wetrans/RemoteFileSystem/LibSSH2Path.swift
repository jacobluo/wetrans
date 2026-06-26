import Foundation

public enum LibSSH2Path {
    private static let fileTypeMask: UInt64 = 0o170000
    private static let directoryType: UInt64 = 0o040000
    private static let regularType: UInt64 = 0o100000
    private static let symlinkType: UInt64 = 0o120000

    public static func join(directory: String, name: String) -> String {
        if directory == "/" {
            return "/\(name)"
        }
        if directory.hasSuffix("/") {
            return "\(directory)\(name)"
        }
        return "\(directory)/\(name)"
    }

    public static func isDirectory(permissions: UInt64) -> Bool {
        permissions & fileTypeMask == directoryType
    }

    public static func isSymlink(permissions: UInt64) -> Bool {
        permissions & fileTypeMask == symlinkType
    }

    public static func permissionsText(from permissions: UInt64) -> String {
        let typeCharacter: Character
        switch permissions & fileTypeMask {
        case directoryType:
            typeCharacter = "d"
        case symlinkType:
            typeCharacter = "l"
        case regularType:
            typeCharacter = "-"
        default:
            typeCharacter = "-"
        }

        let flags: [(UInt64, Character)] = [
            (0o400, "r"), (0o200, "w"), (0o100, "x"),
            (0o040, "r"), (0o020, "w"), (0o010, "x"),
            (0o004, "r"), (0o002, "w"), (0o001, "x")
        ]
        let mode = flags.map { bit, character in
            permissions & bit == bit ? character : "-"
        }
        return String([typeCharacter] + mode)
    }
}
