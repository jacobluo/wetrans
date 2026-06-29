import Combine
import Foundation

public enum FileDeletePanel: Equatable, Sendable {
    case local
    case remote
}

public struct FileDeleteConfirmation: Identifiable, Equatable, Sendable {
    public let id: String
    public let panel: FileDeletePanel
    public let hostId: UUID?
    public let items: [FileItem]
    public let title: String
    public let message: String
    public let actionTitle: String

    public init(
        panel: FileDeletePanel,
        hostId: UUID?,
        items: [FileItem],
        title: String,
        message: String,
        actionTitle: String = "Delete"
    ) {
        self.panel = panel
        self.hostId = hostId
        self.items = items
        self.title = title
        self.message = message
        self.actionTitle = actionTitle
        self.id = "\(panel)-\(hostId?.uuidString ?? "local")-\(items.map(\.id).joined(separator: "|"))"
    }
}

@MainActor
public final class MainBrowserViewModel: ObservableObject {
    @Published public private(set) var hosts: [SavedHost] = []
    @Published public private(set) var selectedHost: SavedHost?
    @Published public private(set) var localPanel: FilePanelState
    @Published public private(set) var remotePanel: FilePanelState
    @Published public private(set) var pendingHostKeyTrust: TrustedHostKey?
    @Published public private(set) var pendingDeleteConfirmation: FileDeleteConfirmation?

    public let sidebarViewModel: HostSidebarViewModel
    public let transferQueueViewModel: TransferQueueViewModel

    private let hostCatalog: HostCatalog
    private let hostSessionManager: HostSessionManager
    private let trustedHostStore: TrustedHostStore
    private let localFileSystem: LocalFileSystem
    private let transferQueue: TransferQueue
    private let fileRevealer: FileRevealer
    private let pasteboardWriter: PasteboardWriting
    private let logger: DiagnosticLogging
    private let defaultLocalPath: () -> String
    private var localRefreshTask: Task<Void, Never>?
    private var transferQueueEventsTask: Task<Void, Never>?
    private var fileOperationClipboard: FileOperationClipboard?

    public convenience init() {
        let credentialStore = KeychainCredentialStore()
        let hostCatalog = FileHostCatalog(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory)
        let trustedHostStore = FileTrustedHostStore(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory)
        let browsingRemoteFileSystem = LibSSH2RemoteFileSystem(trustedHostStore: trustedHostStore)
        let transferRemoteFileSystem = LibSSH2RemoteFileSystem(trustedHostStore: trustedHostStore)
        let transferConnectionProvider = HostCatalogTransferConnectionProvider(
            hostCatalog: hostCatalog,
            credentialStore: credentialStore,
            remoteFileSystem: transferRemoteFileSystem
        )
        self.init(
            hostCatalog: hostCatalog,
            hostSessionManager: HostSessionManager(
                remoteFileSystem: browsingRemoteFileSystem,
                credentialStore: credentialStore
            ),
            trustedHostStore: trustedHostStore,
            localFileSystem: FileManagerLocalFileSystem(),
            transferQueue: TransferQueue(
                engine: SFTPTransferEngine(
                    connectionProvider: transferConnectionProvider,
                    remoteFileSystem: transferRemoteFileSystem
                ),
                historyStore: FileTransferHistoryStore()
            ),
            fileRevealer: NSWorkspaceFileRevealer(),
            pasteboardWriter: SystemPasteboardWriter(),
            logger: OSLogDiagnosticLogger()
        )
    }

    public init(
        hostCatalog: HostCatalog,
        hostSessionManager: HostSessionManager,
        trustedHostStore: TrustedHostStore = FileTrustedHostStore(
            applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory
        ),
        localFileSystem: LocalFileSystem,
        transferQueue: TransferQueue = TransferQueue(engine: UnavailableTransferEngine()),
        fileRevealer: FileRevealer = NSWorkspaceFileRevealer(),
        pasteboardWriter: PasteboardWriting = SystemPasteboardWriter(),
        logger: DiagnosticLogging = OSLogDiagnosticLogger(),
        sidebarViewModel: HostSidebarViewModel = HostSidebarViewModel(),
        defaultLocalPath: @escaping () -> String = {
            FileManager.default.homeDirectoryForCurrentUser.path
        }
    ) {
        self.hostCatalog = hostCatalog
        self.hostSessionManager = hostSessionManager
        self.trustedHostStore = trustedHostStore
        self.localFileSystem = localFileSystem
        self.transferQueue = transferQueue
        self.fileRevealer = fileRevealer
        self.pasteboardWriter = pasteboardWriter
        self.logger = logger
        self.transferQueueViewModel = TransferQueueViewModel(queue: transferQueue)
        self.sidebarViewModel = sidebarViewModel
        self.defaultLocalPath = defaultLocalPath
        self.localPanel = FilePanelState(title: "Local", path: defaultLocalPath())
        self.remotePanel = FilePanelState(title: "Remote", path: "", loadingState: .idle)
        startTransferQueueEventObservation()
    }

    deinit {
        localRefreshTask?.cancel()
        transferQueueEventsTask?.cancel()
    }

    public func loadHosts() throws {
        hosts = try hostCatalog.load()
        sidebarViewModel.update(hosts: hosts)
    }

    public func select(hostId: UUID?) {
        guard let hostId, let host = hosts.first(where: { $0.id == hostId }) else {
            selectedHost = nil
            if sidebarViewModel.selectedHostId != nil {
                sidebarViewModel.selectedHostId = nil
            }
            remotePanel = FilePanelState(
                title: "Remote",
                path: "",
                loadingState: .failed("Select a host to browse remote files.")
            )
            return
        }

        selectedHost = host
        if sidebarViewModel.selectedHostId != host.id {
            sidebarViewModel.select(host: host)
        }

        let state = hostSessionManager.state(for: host)
        localPanel = FilePanelState(title: "Local", path: state.currentLocalPath)
        remotePanel = FilePanelState(title: host.displayName, path: state.currentRemotePath)
    }

    public func refreshLocal() {
        let path = localPanel.path
        localPanel.loadingState = .loading
        localRefreshTask?.cancel()

        let localFileSystem = localFileSystem
        localRefreshTask = Task { [weak self] in
            let result = await Task.detached(priority: .userInitiated) {
                Result {
                    try localFileSystem.listDirectory(path)
                }
            }.value

            guard !Task.isCancelled else {
                return
            }

            await MainActor.run {
                guard let self, self.localPanel.path == path else {
                    return
                }
                switch result {
                case .success(let items):
                    self.localPanel.loadingState = items.isEmpty ? .empty : .loaded(items)
                case .failure(let error):
                    let message = Self.message(forLocalError: error)
                    self.logger.log(
                        .localRefreshFailed,
                        message: message,
                        metadata: ["path": path]
                    )
                    self.localPanel.loadingState = .failed(message)
                }
            }
        }
    }

    public func goUpLocal() {
        let parent = BrowserPath.localParent(of: localPanel.path)
        guard parent != localPanel.path else {
            refreshLocal()
            return
        }
        updateLocalPath(parent)
        refreshLocal()
    }

    public func enterLocalPath(_ path: String) {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            refreshLocal()
            return
        }
        updateLocalPath(path)
        refreshLocal()
    }

    public func openLocalItem(_ item: FileItem) {
        guard item.isDirectory else {
            selectLocalItem(item)
            return
        }
        updateLocalPath(item.path)
        refreshLocal()
    }

    public var canUploadSelection: Bool {
        selectedHost != nil && !localPanel.selectedItems.isEmpty
    }

    public var canDownloadSelection: Bool {
        selectedHost != nil && !remotePanel.selectedItems.isEmpty
    }

    public func refreshRemote() async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host to browse remote files.")
            return
        }

        remotePanel.loadingState = .loading
        do {
            let items = try await hostSessionManager.listRemoteDirectory(for: host)
            pendingHostKeyTrust = nil
            let state = hostSessionManager.state(for: host)
            remotePanel.path = state.currentRemotePath
            remotePanel.loadingState = items.isEmpty ? .empty : .loaded(items)
            try? hostCatalog.markConnected(hostId: host.id, at: Date())
            try? hostCatalog.updatePaths(hostId: host.id, local: nil, remote: state.currentRemotePath)
        } catch RemoteFileSystemError.hostKeyRequiresTrust(let candidate) {
            pendingHostKeyTrust = candidate
            let message = Self.message(forRemoteError: RemoteFileSystemError.hostKeyRequiresTrust(candidate))
            logger.log(.remoteRefreshFailed, message: message, metadata: ["path": remotePanel.path, "host": host.displayName])
            remotePanel.loadingState = .failed(message)
        } catch {
            let message = Self.message(forRemoteError: error)
            logger.log(.remoteRefreshFailed, message: message, metadata: ["path": remotePanel.path, "host": host.displayName])
            remotePanel.loadingState = .failed(message)
        }
    }

    public var pendingHostKeyTrustMessage: String {
        guard let key = pendingHostKeyTrust else {
            return ""
        }
        return """
        \(key.hostname):\(key.port)
        \(key.keyType)
        \(key.fingerprintSHA256)
        """
    }

    public func cancelPendingHostKeyTrust() {
        pendingHostKeyTrust = nil
    }

    public func disconnect(hostId: UUID) async {
        await hostSessionManager.disconnect(hostId: hostId)
    }

    public func disconnectIdleSessions(now: Date = Date(), idleTimeout: TimeInterval = 15 * 60) async {
        await hostSessionManager.disconnectIdleSessions(now: now, idleTimeout: idleTimeout)
    }

    public func trustPendingHostKeyAndRefresh() async {
        guard let key = pendingHostKeyTrust else {
            return
        }
        do {
            try trustedHostStore.trust(key)
            pendingHostKeyTrust = nil
            await refreshRemote()
        } catch {
            remotePanel.loadingState = .failed("Could not save trusted host key: \(error.localizedDescription)")
        }
    }

    public func goUpRemote() async {
        let parent = BrowserPath.remoteParent(of: remotePanel.path)
        guard parent != remotePanel.path else {
            await refreshRemote()
            return
        }
        updateRemotePath(parent)
        await refreshRemote()
    }

    public func enterRemotePath(_ path: String) async {
        let path = path.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !path.isEmpty else {
            await refreshRemote()
            return
        }
        updateRemotePath(path)
        await refreshRemote()
    }

    public func openRemoteItem(_ item: FileItem) async {
        guard item.isDirectory else {
            selectRemoteItem(item)
            return
        }
        updateRemotePath(item.path)
        await refreshRemote()
    }

    public func selectLocalItem(_ item: FileItem, intent: FilePanelSelectionIntent = .replace) {
        select(item.id, intent: intent, in: &localPanel)
    }

    public func selectRemoteItem(_ item: FileItem, intent: FilePanelSelectionIntent = .replace) {
        select(item.id, intent: intent, in: &remotePanel)
    }

    public func revealLocalItemInFinder(_ item: FileItem) {
        fileRevealer.reveal(path: item.path)
    }

    public func copyRemotePath(_ item: FileItem) {
        pasteboardWriter.writeString(item.path)
    }

    public var canPasteIntoLocal: Bool {
        fileOperationClipboard != nil
    }

    public var canPasteIntoRemote: Bool {
        guard fileOperationClipboard != nil else {
            return false
        }
        return selectedHost != nil
    }

    public func copyLocalItems(_ item: FileItem) {
        fileOperationClipboard = .local(items: contextTransferItems(for: item, in: localPanel))
    }

    public func copyRemoteItems(_ item: FileItem) {
        guard let selectedHost else {
            remotePanel.loadingState = .failed("Select a host before copying remote files.")
            return
        }
        fileOperationClipboard = .remote(hostId: selectedHost.id, items: contextTransferItems(for: item, in: remotePanel))
    }

    public func pasteIntoLocal() async {
        guard let fileOperationClipboard else {
            return
        }

        switch fileOperationClipboard {
        case .local(let items):
            pasteLocalItems(items, intoLocalDirectory: localPanel.path)
        case .remote(let hostId, let items):
            guard let host = selectedHost, host.id == hostId else {
                localPanel.loadingState = .failed("Select the source host before pasting copied remote files.")
                return
            }
            let tasks: [TransferTask]
            do {
                tasks = try await DirectoryTransferPlanner(localFileSystem: localFileSystem).downloadTasks(
                    for: items,
                    host: host,
                    localDirectory: localPanel.path,
                    hostSessionManager: hostSessionManager
                )
            } catch {
                let message = Self.message(forRemoteError: error)
                localPanel.loadingState = .failed("Could not prepare pasted download: \(message)")
                return
            }
            await enqueueDownloadTasks(tasks)
        }
    }

    public func pasteIntoRemote() async {
        guard let fileOperationClipboard else {
            return
        }
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host before pasting remote files.")
            return
        }

        switch fileOperationClipboard {
        case .local(let items):
            let tasks: [TransferTask]
            do {
                tasks = try DirectoryTransferPlanner(localFileSystem: localFileSystem).uploadTasks(
                    for: items,
                    host: host,
                    remoteDirectory: remotePanel.path
                )
            } catch {
                remotePanel.loadingState = .failed("Could not prepare pasted upload: \(error.localizedDescription)")
                return
            }
            await enqueueUploadTasks(tasks)
        case .remote(let hostId, let items):
            guard host.id == hostId else {
                remotePanel.loadingState = .failed("Select the source host before pasting copied remote files.")
                return
            }
            await pasteRemoteItems(items, intoRemoteDirectory: remotePanel.path, host: host)
        }
    }

    public func deleteLocalItems(_ item: FileItem) {
        let items = contextTransferItems(for: item, in: localPanel)
        deleteLocalItems(items)
    }

    public func requestDeleteLocalItems(_ item: FileItem) {
        let items = contextTransferItems(for: item, in: localPanel)
        pendingDeleteConfirmation = Self.deleteConfirmation(panel: .local, hostId: nil, items: items)
    }

    public func requestDeleteRemoteItems(_ item: FileItem) {
        let items = contextTransferItems(for: item, in: remotePanel)
        pendingDeleteConfirmation = Self.deleteConfirmation(panel: .remote, hostId: selectedHost?.id, items: items)
    }

    public func cancelPendingDelete() {
        pendingDeleteConfirmation = nil
    }

    public func confirmPendingDelete() async {
        guard let confirmation = pendingDeleteConfirmation else {
            return
        }
        await confirmDelete(confirmation)
    }

    func confirmDelete(_ confirmation: FileDeleteConfirmation) async {
        pendingDeleteConfirmation = nil

        switch confirmation.panel {
        case .local:
            deleteLocalItems(confirmation.items)
        case .remote:
            await deleteRemoteItems(confirmation.items, expectedHostId: confirmation.hostId)
        }
    }

    private func deleteLocalItems(_ items: [FileItem]) {
        do {
            for item in items {
                try localFileSystem.deleteItem(at: item.path)
            }
            localPanel.selectedItemIds.subtract(items.map(\.id))
            refreshLocal()
        } catch {
            localPanel.loadingState = .failed("Could not delete local item: \(Self.message(forLocalError: error))")
        }
    }

    public func deleteRemoteItems(_ item: FileItem) async {
        let items = contextTransferItems(for: item, in: remotePanel)
        await deleteRemoteItems(items, expectedHostId: nil)
    }

    private func deleteRemoteItems(_ items: [FileItem], expectedHostId: UUID?) async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host before deleting remote files.")
            return
        }
        if let expectedHostId, host.id != expectedHostId {
            remotePanel.loadingState = .failed("Select the source host before deleting copied remote files.")
            return
        }
        do {
            for item in items {
                try await hostSessionManager.deleteRemoteItem(item, for: host)
            }
            remotePanel.selectedItemIds.subtract(items.map(\.id))
            await refreshRemote()
        } catch {
            let message = Self.message(forRemoteError: error)
            remotePanel.loadingState = .failed("Could not delete remote item: \(message)")
        }
    }

    public func copyLocalDebugDetail() {
        copyDebugDetail(panelName: "Local", state: localPanel)
    }

    public func copyRemoteDebugDetail() {
        copyDebugDetail(panelName: "Remote", state: remotePanel)
    }

    public func enqueueUpload(_ item: FileItem) async {
        guard let host = selectedHost else {
            localPanel.loadingState = .failed("Select a host before uploading files.")
            return
        }

        let items = contextTransferItems(for: item, in: localPanel)
        let tasks: [TransferTask]
        do {
            tasks = try DirectoryTransferPlanner(localFileSystem: localFileSystem).uploadTasks(
                for: items,
                host: host,
                remoteDirectory: remotePanel.path
            )
        } catch {
            localPanel.loadingState = .failed("Could not prepare upload: \(error.localizedDescription)")
            return
        }

        await enqueueUploadTasks(tasks)
    }

    public func enqueueDownload(_ item: FileItem) async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host before downloading files.")
            return
        }

        let items = contextTransferItems(for: item, in: remotePanel)
        let tasks: [TransferTask]
        do {
            tasks = try await DirectoryTransferPlanner(localFileSystem: localFileSystem).downloadTasks(
                for: items,
                host: host,
                localDirectory: localPanel.path,
                hostSessionManager: hostSessionManager
            )
        } catch {
            let message = Self.message(forRemoteError: error)
            remotePanel.loadingState = .failed("Could not prepare download: \(message)")
            return
        }

        await enqueueDownloadTasks(tasks)
    }

    public func enqueueUploadSelection() async {
        guard let host = selectedHost else {
            localPanel.loadingState = .failed("Select a host before uploading files.")
            return
        }

        let tasks: [TransferTask]
        do {
            tasks = try DirectoryTransferPlanner(localFileSystem: localFileSystem).uploadTasks(
                for: localPanel.selectedItems,
                host: host,
                remoteDirectory: remotePanel.path
            )
        } catch {
            localPanel.loadingState = .failed("Could not prepare upload: \(error.localizedDescription)")
            return
        }

        await enqueueUploadTasks(tasks)
    }

    public func enqueueDownloadSelection() async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host before downloading files.")
            return
        }

        let tasks: [TransferTask]
        do {
            tasks = try await DirectoryTransferPlanner(localFileSystem: localFileSystem).downloadTasks(
                for: remotePanel.selectedItems,
                host: host,
                localDirectory: localPanel.path,
                hostSessionManager: hostSessionManager
            )
        } catch {
            let message = Self.message(forRemoteError: error)
            remotePanel.loadingState = .failed("Could not prepare download: \(message)")
            return
        }

        await enqueueDownloadTasks(tasks)
    }

    private func enqueueUploadTasks(_ tasks: [TransferTask]) async {
        guard !tasks.isEmpty else {
            localPanel.loadingState = .failed("Select one or more files or directories to upload.")
            return
        }

        await transferQueue.enqueue(tasks)
        logger.log(
            .transferTasksEnqueued,
            message: "Enqueued upload tasks",
            metadata: ["count": "\(tasks.count)", "direction": "upload"]
        )
        await transferQueueViewModel.refresh()
    }

    private func enqueueDownloadTasks(_ tasks: [TransferTask]) async {
        guard !tasks.isEmpty else {
            remotePanel.loadingState = .failed("Select one or more files or directories to download.")
            return
        }

        await transferQueue.enqueue(tasks)
        logger.log(
            .transferTasksEnqueued,
            message: "Enqueued download tasks",
            metadata: ["count": "\(tasks.count)", "direction": "download"]
        )
        await transferQueueViewModel.refresh()
    }

    private func copyDebugDetail(panelName: String, state: FilePanelState) {
        guard !state.errorMessage.isEmpty else {
            return
        }
        let detail = DiagnosticDetail(
            panel: panelName,
            path: state.path,
            message: state.errorMessage,
            hostDisplayName: selectedHost?.displayName
        )
        pasteboardWriter.writeString(detail.report)
    }

    private func contextTransferItems(for item: FileItem, in panel: FilePanelState) -> [FileItem] {
        guard panel.selectedItemIds.contains(item.id) else {
            return [item]
        }
        return panel.selectedItems
    }

    private func pasteLocalItems(_ items: [FileItem], intoLocalDirectory directory: String) {
        var occupiedNames = Set(localPanel.loadedItems.map(\.name))
        do {
            for item in items {
                let destinationName = Self.nonConflictingName(for: item.name, occupiedNames: occupiedNames)
                occupiedNames.insert(destinationName)
                try localFileSystem.copyItem(
                    at: item.path,
                    to: BrowserPath.localJoin(directory: directory, name: destinationName)
                )
            }
            refreshLocal()
        } catch {
            localPanel.loadingState = .failed("Could not paste local item: \(Self.message(forLocalError: error))")
        }
    }

    private func pasteRemoteItems(_ items: [FileItem], intoRemoteDirectory directory: String, host: SavedHost) async {
        var occupiedNames = Set(remotePanel.loadedItems.map(\.name))
        do {
            for item in items {
                let destinationName = Self.nonConflictingName(for: item.name, occupiedNames: occupiedNames)
                occupiedNames.insert(destinationName)
                try await hostSessionManager.copyRemoteItem(
                    from: item.path,
                    to: BrowserPath.remoteJoin(directory: directory, name: destinationName),
                    for: host
                )
            }
            await refreshRemote()
        } catch {
            let message = Self.message(forRemoteError: error)
            remotePanel.loadingState = .failed("Could not paste remote item: \(message)")
        }
    }

    private static func nonConflictingName(for name: String, occupiedNames: Set<String>) -> String {
        let url = URL(fileURLWithPath: name)
        let baseName = url.deletingPathExtension().lastPathComponent
        let fileExtension = url.pathExtension
        let hasExtension = !fileExtension.isEmpty && !name.hasPrefix(".")

        func candidate(_ suffix: String) -> String {
            guard hasExtension else {
                return "\(name)\(suffix)"
            }
            return "\(baseName)\(suffix).\(fileExtension)"
        }

        let first = candidate(" copy")
        guard occupiedNames.contains(first) else {
            return first
        }

        var index = 2
        while true {
            let value = candidate(" copy \(index)")
            if !occupiedNames.contains(value) {
                return value
            }
            index += 1
        }
    }

    private static func deleteConfirmation(
        panel: FileDeletePanel,
        hostId: UUID?,
        items: [FileItem]
    ) -> FileDeleteConfirmation {
        let title: String
        if items.count == 1, let item = items.first {
            title = "Delete \(item.name)?"
        } else {
            title = "Delete \(items.count) items?"
        }

        let message: String
        switch panel {
        case .local:
            if items.count == 1, let item = items.first {
                message = "Move \"\(item.name)\" to the Trash?"
            } else {
                message = "Move \(items.count) items to the Trash?"
            }
        case .remote:
            if items.count == 1, let item = items.first {
                message = "This will permanently delete \"\(item.name)\" from the remote host. This cannot be undone."
            } else {
                message = "This will permanently delete \(items.count) items from the remote host. This cannot be undone."
            }
        }

        return FileDeleteConfirmation(
            panel: panel,
            hostId: hostId,
            items: items,
            title: title,
            message: message
        )
    }

    private func updateLocalPath(_ path: String) {
        localPanel.path = path
        localPanel.selectedItemIds = []
        if let host = selectedHost {
            hostSessionManager.updateLocalPath(path, for: host)
            try? hostCatalog.updatePaths(hostId: host.id, local: path, remote: nil)
        }
    }

    private func updateRemotePath(_ path: String) {
        remotePanel.path = path
        remotePanel.selectedItemIds = []
        if let host = selectedHost {
            hostSessionManager.updateRemotePath(path, for: host)
            try? hostCatalog.updatePaths(hostId: host.id, local: nil, remote: path)
        }
    }

    private func startTransferQueueEventObservation() {
        transferQueueEventsTask?.cancel()
        transferQueueEventsTask = Task { [weak self, transferQueue] in
            let events = await transferQueue.events()
            for await event in events {
                await self?.handleTransferQueueEvent(event)
            }
        }
    }

    private func handleTransferQueueEvent(_ event: TransferQueueEvent) async {
        await transferQueueViewModel.refresh()
        logger.log(
            .transferCompletionObserved,
            message: "Observed transfer status change",
            metadata: [
                "file": event.task.fileName,
                "status": "\(event.task.status)",
                "direction": "\(event.task.direction)"
            ]
        )
        guard event.task.status == .succeeded else {
            return
        }
        guard selectedHost?.id == event.task.hostId else {
            return
        }

        switch event.task.direction {
        case .upload:
            let destinationDirectory = BrowserPath.remoteParent(of: event.task.remotePath)
            guard remotePanel.path == destinationDirectory else {
                return
            }
            await refreshRemote()
        case .download:
            let destinationDirectory = BrowserPath.localParent(of: event.task.localPath)
            guard localPanel.path == destinationDirectory else {
                return
            }
            refreshLocal()
        }
    }

    private func select(_ itemId: String, intent: FilePanelSelectionIntent, in panel: inout FilePanelState) {
        switch intent {
        case .replace:
            panel.selectedItemIds = [itemId]
        case .extend:
            if panel.selectedItemIds.contains(itemId) {
                panel.selectedItemIds.remove(itemId)
            } else {
                panel.selectedItemIds.insert(itemId)
            }
        }
    }

    private static func message(forLocalError error: Error) -> String {
        switch error {
        case LocalFileSystemError.notDirectory(let path):
            return "Not a directory: \(path)"
        case LocalFileSystemError.cannotRead(let path):
            return "Cannot read local directory: \(path)"
        case LocalFileSystemError.cannotCopy(let source, let destination):
            return "Cannot copy \(source) to \(destination)"
        case LocalFileSystemError.cannotDelete(let path):
            return "Cannot delete local item: \(path)"
        default:
            return "Cannot load local directory: \(error.localizedDescription)"
        }
    }

    private static func message(forRemoteError error: Error) -> String {
        switch error {
        case RemoteFileSystemError.hostKeyRequiresTrust:
            return "Host key requires confirmation before browsing."
        case RemoteFileSystemError.hostKeyChanged:
            return "Host key changed. Remote browsing is blocked."
        case RemoteFileSystemError.disconnected:
            return "Remote connection is disconnected. Refresh to retry."
        case RemoteFileSystemError.notDirectory(let path):
            return "Not a remote directory: \(path)"
        case RemoteFileSystemError.permissionDenied(let path):
            return "Permission denied: \(path)"
        case RemoteFileSystemError.connectionFailed(let message):
            if let diagnostic = SFTPStartupOutputDiagnostic(message: message) {
                return diagnostic.userMessage
            }
            return message
        default:
            return "Cannot load remote directory: \(error.localizedDescription)"
        }
    }
}

extension MainBrowserViewModel: HostSessionCleaning {}

private enum FileOperationClipboard {
    case local(items: [FileItem])
    case remote(hostId: UUID, items: [FileItem])
}
