import Foundation

public final class FileSSHConfigScanner: SSHConfigScanner {
    private let configURL: URL
    private let fileManager: FileManager

    public init(
        configURL: URL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ssh")
            .appendingPathComponent("config"),
        fileManager: FileManager = .default
    ) {
        self.configURL = configURL
        self.fileManager = fileManager
    }

    public func scanDefaultConfig() throws -> [SSHConfigAlias] {
        try scanFile(configURL, visited: [])
    }

    public static func scanAliases(in text: String) throws -> [SSHConfigAlias] {
        aliases(in: text, sourcePath: nil)
    }

    private func scanFile(_ url: URL, visited: Set<URL>) throws -> [SSHConfigAlias] {
        let normalizedURL = url.standardizedFileURL
        guard !visited.contains(normalizedURL) else {
            return []
        }

        let text = try String(contentsOf: normalizedURL, encoding: .utf8)
        var aliases = Self.aliases(in: text, sourcePath: normalizedURL.path)

        for includePattern in Self.includePatterns(in: text) {
            let includeURLs = try resolveInclude(pattern: includePattern, relativeTo: normalizedURL)
            for includeURL in includeURLs {
                aliases.append(contentsOf: try scanFile(includeURL, visited: visited.union([normalizedURL])))
            }
        }

        return deduplicated(aliases)
    }

    private static func aliases(in text: String, sourcePath: String?) -> [SSHConfigAlias] {
        var result: [SSHConfigAlias] = []

        for line in text.components(separatedBy: .newlines) {
            let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("host ") else {
                continue
            }

            let tokens = trimmed
                .dropFirst(5)
                .split(whereSeparator: { $0 == " " || $0 == "\t" })
                .map(String.init)

            for token in tokens where isSelectableAlias(token) {
                result.append(SSHConfigAlias(alias: token, sourcePath: sourcePath))
            }
        }

        return deduplicated(result)
    }

    private static func includePatterns(in text: String) -> [String] {
        text.components(separatedBy: .newlines).compactMap { line in
            let trimmed = stripComment(from: line).trimmingCharacters(in: .whitespacesAndNewlines)
            guard trimmed.lowercased().hasPrefix("include ") else {
                return nil
            }
            return String(trimmed.dropFirst(8)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        .filter { !$0.isEmpty }
    }

    private static func isSelectableAlias(_ alias: String) -> Bool {
        if alias.hasPrefix("!") {
            return false
        }
        if alias.contains("*") || alias.contains("?") {
            return false
        }
        return !alias.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private static func stripComment(from line: String) -> String {
        guard let hashIndex = line.firstIndex(of: "#") else {
            return line
        }
        return String(line[..<hashIndex])
    }

    private func resolveInclude(pattern: String, relativeTo configURL: URL) throws -> [URL] {
        let expandedPattern = expandTilde(in: pattern)
        let absolutePattern: String
        if expandedPattern.hasPrefix("/") {
            absolutePattern = expandedPattern
        } else {
            absolutePattern = configURL.deletingLastPathComponent().appendingPathComponent(expandedPattern).path
        }

        if absolutePattern.contains("*") || absolutePattern.contains("?") {
            return try fileManager.contentsOfDirectory(
                at: URL(fileURLWithPath: absolutePattern).deletingLastPathComponent(),
                includingPropertiesForKeys: nil
            )
            .filter { fnmatch(absolutePattern, $0.path, 0) == 0 }
            .sorted { $0.path < $1.path }
        }

        return [URL(fileURLWithPath: absolutePattern)]
    }

    private func expandTilde(in path: String) -> String {
        guard path == "~" || path.hasPrefix("~/") else {
            return path
        }
        return fileManager.homeDirectoryForCurrentUser.path + String(path.dropFirst())
    }
}

private func deduplicated(_ aliases: [SSHConfigAlias]) -> [SSHConfigAlias] {
    var seen = Set<String>()
    return aliases.filter { seen.insert($0.alias).inserted }
}

