import Foundation

public final class FileManagerLocalFileSystem: LocalFileSystem {
    private let fileManager: FileManager

    public init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
    }

    public func listDirectory(_ path: String) throws -> [FileItem] {
        var isDirectory: ObjCBool = false
        guard fileManager.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw LocalFileSystemError.notDirectory(path)
        }

        let directoryURL = URL(fileURLWithPath: path)
        let urls: [URL]
        do {
            urls = try fileManager.contentsOfDirectory(
                at: directoryURL,
                includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey, .fileSizeKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
            )
        } catch {
            throw LocalFileSystemError.cannotRead(path)
        }

        return try urls
            .map(makeFileItem)
            .sorted { lhs, rhs in
                if lhs.isDirectory != rhs.isDirectory {
                    return lhs.isDirectory && !rhs.isDirectory
                }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
    }

    private func makeFileItem(url: URL) throws -> FileItem {
        let values = try url.resourceValues(forKeys: [
            .isDirectoryKey,
            .isSymbolicLinkKey,
            .fileSizeKey,
            .contentModificationDateKey
        ])
        let isDirectory = values.isDirectory ?? false
        return FileItem(
            name: url.lastPathComponent,
            path: url.path,
            isDirectory: isDirectory,
            isSymlink: values.isSymbolicLink ?? false,
            size: isDirectory ? nil : values.fileSize.map(UInt64.init),
            modifiedAt: values.contentModificationDate,
            permissions: nil
        )
    }
}

