import Foundation

public struct DirectoryTransferPlanner: Sendable {
    private let localFileSystem: LocalFileSystem

    public init(localFileSystem: LocalFileSystem) {
        self.localFileSystem = localFileSystem
    }

    public func uploadTasks(
        for items: [FileItem],
        host: SavedHost,
        remoteDirectory: String
    ) throws -> [TransferTask] {
        var tasks: [TransferTask] = []
        for item in items {
            try appendUploadTasks(
                item: item,
                host: host,
                remoteDirectory: remoteDirectory,
                tasks: &tasks
            )
        }
        return tasks
    }

    public func downloadTasks(
        for items: [FileItem],
        host: SavedHost,
        localDirectory: String,
        hostSessionManager: HostSessionManager
    ) async throws -> [TransferTask] {
        var tasks: [TransferTask] = []
        for item in items {
            try await appendDownloadTasks(
                item: item,
                host: host,
                localDirectory: localDirectory,
                hostSessionManager: hostSessionManager,
                tasks: &tasks
            )
        }
        return tasks
    }

    private func appendUploadTasks(
        item: FileItem,
        host: SavedHost,
        remoteDirectory: String,
        tasks: inout [TransferTask]
    ) throws {
        if item.isDirectory {
            guard !item.isSymlink else {
                return
            }
            let childRemoteDirectory = BrowserPath.remoteJoin(directory: remoteDirectory, name: item.name)
            let childItems = try localFileSystem.listDirectory(item.path)
            for childItem in childItems {
                try appendUploadTasks(
                    item: childItem,
                    host: host,
                    remoteDirectory: childRemoteDirectory,
                    tasks: &tasks
                )
            }
            return
        }

        tasks.append(
            TransferTask(
                hostId: host.id,
                hostDisplayName: host.displayName,
                direction: .upload,
                localPath: item.path,
                remotePath: BrowserPath.remoteJoin(directory: remoteDirectory, name: item.name),
                fileName: item.name,
                totalBytes: item.size
            )
        )
    }

    private func appendDownloadTasks(
        item: FileItem,
        host: SavedHost,
        localDirectory: String,
        hostSessionManager: HostSessionManager,
        tasks: inout [TransferTask]
    ) async throws {
        if item.isDirectory {
            guard !item.isSymlink else {
                return
            }
            let childLocalDirectory = BrowserPath.localJoin(directory: localDirectory, name: item.name)
            let childItems = try await hostSessionManager.listRemoteDirectory(path: item.path, for: host)
            for childItem in childItems {
                try await appendDownloadTasks(
                    item: childItem,
                    host: host,
                    localDirectory: childLocalDirectory,
                    hostSessionManager: hostSessionManager,
                    tasks: &tasks
                )
            }
            return
        }

        tasks.append(
            TransferTask(
                hostId: host.id,
                hostDisplayName: host.displayName,
                direction: .download,
                localPath: BrowserPath.localJoin(directory: localDirectory, name: item.name),
                remotePath: item.path,
                fileName: item.name,
                totalBytes: item.size
            )
        )
    }
}
