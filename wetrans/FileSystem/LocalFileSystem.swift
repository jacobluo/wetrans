import Foundation

public protocol LocalFileSystem: Sendable {
    func listDirectory(_ path: String) throws -> [FileItem]
    func copyItem(at sourcePath: String, to destinationPath: String) throws
    func deleteItem(at path: String) throws
}

public enum LocalFileSystemError: Error, Equatable {
    case notDirectory(String)
    case cannotRead(String)
    case cannotCopy(source: String, destination: String)
    case cannotDelete(String)
}
