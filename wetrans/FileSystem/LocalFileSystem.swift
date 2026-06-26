import Foundation

public protocol LocalFileSystem: Sendable {
    func listDirectory(_ path: String) throws -> [FileItem]
}

public enum LocalFileSystemError: Error, Equatable {
    case notDirectory(String)
    case cannotRead(String)
}
