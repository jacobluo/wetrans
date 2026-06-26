import Combine
import Foundation

@MainActor
public final class MainBrowserViewModel: ObservableObject {
    @Published public private(set) var hosts: [SavedHost] = []
    @Published public private(set) var selectedHost: SavedHost?
    @Published public private(set) var localPanel: FilePanelState
    @Published public private(set) var remotePanel: FilePanelState
    @Published public private(set) var pendingHostKeyTrust: TrustedHostKey?

    public let sidebarViewModel: HostSidebarViewModel
    public let transferQueueViewModel: TransferQueueViewModel

    private let hostCatalog: HostCatalog
    private let hostSessionManager: HostSessionManager
    private let trustedHostStore: TrustedHostStore
    private let localFileSystem: LocalFileSystem
    private let transferQueue: TransferQueue
    private let fileRevealer: FileRevealer
    private let pasteboardWriter: PasteboardWriting
    private let defaultLocalPath: () -> String
    private var localRefreshTask: Task<Void, Never>?
    private var transferQueueEventsTask: Task<Void, Never>?

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
            pasteboardWriter: SystemPasteboardWriter()
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
        sidebarViewModel: HostSidebarViewModel = HostSidebarViewModel(),
        defaultLocalPath: @escaping () -> String = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
    ) {
        self.hostCatalog = hostCatalog
        self.hostSessionManager = hostSessionManager
        self.trustedHostStore = trustedHostStore
        self.localFileSystem = localFileSystem
        self.transferQueue = transferQueue
        self.fileRevealer = fileRevealer
        self.pasteboardWriter = pasteboardWriter
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
                    self.localPanel.loadingState = .failed(Self.message(forLocalError: error))
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

    public func openLocalItem(_ item: FileItem) {
        guard item.isDirectory else {
            selectLocalItem(item)
            return
        }
        updateLocalPath(item.path)
        refreshLocal()
    }

    public var canUploadSelection: Bool {
        selectedHost != nil && localPanel.selectedItems.contains { !$0.isDirectory }
    }

    public var canDownloadSelection: Bool {
        selectedHost != nil && remotePanel.selectedItems.contains { !$0.isDirectory }
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
            remotePanel.loadingState = .failed(Self.message(forRemoteError: RemoteFileSystemError.hostKeyRequiresTrust(candidate)))
        } catch {
            remotePanel.loadingState = .failed(Self.message(forRemoteError: error))
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

    public func enqueueUpload(_ item: FileItem) async {
        guard let host = selectedHost else {
            localPanel.loadingState = .failed("Select a host before uploading files.")
            return
        }

        let items = contextTransferItems(for: item, in: localPanel)
        let tasks = items
            .filter { !$0.isDirectory }
            .map { selectedItem in
                TransferTask(
                    hostId: host.id,
                    hostDisplayName: host.displayName,
                    direction: .upload,
                    localPath: selectedItem.path,
                    remotePath: BrowserPath.remoteJoin(directory: remotePanel.path, name: selectedItem.name),
                    fileName: selectedItem.name,
                    totalBytes: selectedItem.size
                )
            }
        guard !tasks.isEmpty else {
            localPanel.loadingState = .failed("Select a file to upload.")
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
        let tasks = items
            .filter { !$0.isDirectory }
            .map { selectedItem in
                TransferTask(
                    hostId: host.id,
                    hostDisplayName: host.displayName,
                    direction: .download,
                    localPath: BrowserPath.localJoin(directory: localPanel.path, name: selectedItem.name),
                    remotePath: selectedItem.path,
                    fileName: selectedItem.name,
                    totalBytes: selectedItem.size
                )
            }
        guard !tasks.isEmpty else {
            remotePanel.loadingState = .failed("Select a file to download.")
            return
        }

        await enqueueDownloadTasks(tasks)
    }

    public func enqueueUploadSelection() async {
        guard let host = selectedHost else {
            localPanel.loadingState = .failed("Select a host before uploading files.")
            return
        }

        let tasks = localPanel.selectedItems
            .filter { !$0.isDirectory }
            .map { item in
                TransferTask(
                    hostId: host.id,
                    hostDisplayName: host.displayName,
                    direction: .upload,
                    localPath: item.path,
                    remotePath: BrowserPath.remoteJoin(directory: remotePanel.path, name: item.name),
                    fileName: item.name,
                    totalBytes: item.size
                )
            }

        await enqueueUploadTasks(tasks)
    }

    public func enqueueDownloadSelection() async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host before downloading files.")
            return
        }

        let tasks = remotePanel.selectedItems
            .filter { !$0.isDirectory }
            .map { item in
                TransferTask(
                    hostId: host.id,
                    hostDisplayName: host.displayName,
                    direction: .download,
                    localPath: BrowserPath.localJoin(directory: localPanel.path, name: item.name),
                    remotePath: item.path,
                    fileName: item.name,
                    totalBytes: item.size
                )
            }

        await enqueueDownloadTasks(tasks)
    }

    private func enqueueUploadTasks(_ tasks: [TransferTask]) async {
        guard !tasks.isEmpty else {
            localPanel.loadingState = .failed("Select one or more files to upload.")
            return
        }

        await transferQueue.enqueue(tasks)
        await transferQueueViewModel.refresh()
    }

    private func enqueueDownloadTasks(_ tasks: [TransferTask]) async {
        guard !tasks.isEmpty else {
            remotePanel.loadingState = .failed("Select one or more files to download.")
            return
        }

        await transferQueue.enqueue(tasks)
        await transferQueueViewModel.refresh()
    }

    private func contextTransferItems(for item: FileItem, in panel: FilePanelState) -> [FileItem] {
        guard panel.selectedItemIds.contains(item.id) else {
            return [item]
        }
        return panel.selectedItems
    }

    private func updateLocalPath(_ path: String) {
        localPanel.path = path
        if let host = selectedHost {
            hostSessionManager.updateLocalPath(path, for: host)
            try? hostCatalog.updatePaths(hostId: host.id, local: path, remote: nil)
        }
    }

    private func updateRemotePath(_ path: String) {
        remotePanel.path = path
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
            return message
        default:
            return "Cannot load remote directory: \(error.localizedDescription)"
        }
    }
}
