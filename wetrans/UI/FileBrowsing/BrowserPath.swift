import Foundation

public enum BrowserPath {
    public static func remoteParent(of path: String) -> String {
        let trimmed = path.removingTrailingSlashes
        guard trimmed != "/" else {
            return "/"
        }
        guard let separator = trimmed.lastIndex(of: "/") else {
            return "."
        }
        if separator == trimmed.startIndex {
            return "/"
        }
        return String(trimmed[..<separator])
    }

    public static func remoteJoin(directory: String, name: String) -> String {
        let base = directory.removingTrailingSlashes
        if base == "/" {
            return "/\(name)"
        }
        return "\(base)/\(name)"
    }

    public static func localParent(of path: String) -> String {
        URL(fileURLWithPath: path).deletingLastPathComponent().path
    }

    public static func localJoin(directory: String, name: String) -> String {
        URL(fileURLWithPath: directory).appendingPathComponent(name).path
    }
}

private extension String {
    var removingTrailingSlashes: String {
        guard count > 1 else {
            return self
        }
        var value = self
        while value.count > 1 && value.hasSuffix("/") {
            value.removeLast()
        }
        return value
    }
}
