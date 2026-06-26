import Foundation

public struct FileItem: Identifiable, Equatable, Sendable {
    public let id: String
    public let name: String
    public let path: String
    public let isDirectory: Bool
    public let isSymlink: Bool
    public let size: UInt64?
    public let modifiedAt: Date?
    public let permissions: String?

    public init(
        id: String? = nil,
        name: String,
        path: String,
        isDirectory: Bool,
        isSymlink: Bool = false,
        size: UInt64? = nil,
        modifiedAt: Date? = nil,
        permissions: String? = nil
    ) {
        self.id = id ?? path
        self.name = name
        self.path = path
        self.isDirectory = isDirectory
        self.isSymlink = isSymlink
        self.size = size
        self.modifiedAt = modifiedAt
        self.permissions = permissions
    }
}
