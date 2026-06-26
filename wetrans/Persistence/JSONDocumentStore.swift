import Foundation

public enum JSONDocumentStoreError: Error, Equatable {
    case unsupportedSchemaVersion(Int)
}

public final class JSONDocumentStore<Document: Codable> {
    private let url: URL
    private let decoder: JSONDecoder
    private let encoder: JSONEncoder
    private let fileManager: FileManager

    public init(
        url: URL,
        decoder: JSONDecoder = .wetransDefault,
        encoder: JSONEncoder = .wetransDefault,
        fileManager: FileManager = .default
    ) {
        self.url = url
        self.decoder = decoder
        self.encoder = encoder
        self.fileManager = fileManager
    }

    public func load(default defaultDocument: @autoclosure () -> Document) throws -> Document {
        guard fileManager.fileExists(atPath: url.path) else {
            return defaultDocument()
        }
        let data = try Data(contentsOf: url)
        return try decoder.decode(Document.self, from: data)
    }

    public func save(_ document: Document) throws {
        let directoryURL = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: directoryURL, withIntermediateDirectories: true)

        let data = try encoder.encode(document)
        let temporaryURL = directoryURL.appendingPathComponent(".\(url.lastPathComponent).tmp-\(UUID().uuidString)")

        do {
            try data.write(to: temporaryURL, options: [.withoutOverwriting])
            if fileManager.fileExists(atPath: url.path) {
                _ = try fileManager.replaceItemAt(url, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: url)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        }
    }
}

public extension JSONDecoder {
    static var wetransDefault: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

public extension JSONEncoder {
    static var wetransDefault: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}

