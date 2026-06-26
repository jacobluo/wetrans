import Combine
import Foundation

@MainActor
public final class MainBrowserViewModel: ObservableObject {
    @Published public private(set) var hosts: [SavedHost] = []
    @Published public private(set) var selectedHost: SavedHost?
    @Published public private(set) var localPanel: FilePanelState
    @Published public private(set) var remotePanel: FilePanelState

    public let sidebarViewModel: HostSidebarViewModel

    private let hostCatalog: HostCatalog
    private let hostSessionManager: HostSessionManager
    private let localFileSystem: LocalFileSystem
    private let defaultLocalPath: () -> String

    public convenience init() {
        let credentialStore = KeychainCredentialStore()
        let remoteFileSystem = LibSSH2RemoteFileSystem()
        self.init(
            hostCatalog: FileHostCatalog(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory),
            hostSessionManager: HostSessionManager(
                remoteFileSystem: remoteFileSystem,
                credentialStore: credentialStore
            ),
            localFileSystem: FileManagerLocalFileSystem()
        )
    }

    public init(
        hostCatalog: HostCatalog,
        hostSessionManager: HostSessionManager,
        localFileSystem: LocalFileSystem,
        sidebarViewModel: HostSidebarViewModel = HostSidebarViewModel(),
        defaultLocalPath: @escaping () -> String = {
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
                ?? FileManager.default.homeDirectoryForCurrentUser.path
        }
    ) {
        self.hostCatalog = hostCatalog
        self.hostSessionManager = hostSessionManager
        self.localFileSystem = localFileSystem
        self.sidebarViewModel = sidebarViewModel
        self.defaultLocalPath = defaultLocalPath
        self.localPanel = FilePanelState(title: "Local", path: defaultLocalPath())
        self.remotePanel = FilePanelState(title: "Remote", path: "", loadingState: .idle)
    }

    public func loadHosts() throws {
        hosts = try hostCatalog.load()
        sidebarViewModel.update(hosts: hosts)
    }

    public func select(hostId: UUID?) {
        guard let hostId, let host = hosts.first(where: { $0.id == hostId }) else {
            selectedHost = nil
            sidebarViewModel.selectedHostId = nil
            remotePanel = FilePanelState(
                title: "Remote",
                path: "",
                loadingState: .failed("Select a host to browse remote files.")
            )
            return
        }

        selectedHost = host
        sidebarViewModel.select(host: host)

        let state = hostSessionManager.state(for: host)
        localPanel = FilePanelState(title: "Local", path: state.currentLocalPath)
        remotePanel = FilePanelState(title: host.displayName, path: state.currentRemotePath)
    }

    public func refreshLocal() {
        localPanel.loadingState = .loading
        do {
            let items = try localFileSystem.listDirectory(localPanel.path)
            localPanel.loadingState = items.isEmpty ? .empty : .loaded(items)
        } catch {
            localPanel.loadingState = .failed(Self.message(forLocalError: error))
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
            localPanel.selectedItemIds = [item.id]
            return
        }
        updateLocalPath(item.path)
        refreshLocal()
    }

    public func refreshRemote() async {
        guard let host = selectedHost else {
            remotePanel.loadingState = .failed("Select a host to browse remote files.")
            return
        }

        remotePanel.loadingState = .loading
        do {
            let items = try await hostSessionManager.listRemoteDirectory(for: host)
            let state = hostSessionManager.state(for: host)
            remotePanel.path = state.currentRemotePath
            remotePanel.loadingState = items.isEmpty ? .empty : .loaded(items)
            try? hostCatalog.markConnected(hostId: host.id, at: Date())
            try? hostCatalog.updatePaths(hostId: host.id, local: nil, remote: state.currentRemotePath)
        } catch {
            remotePanel.loadingState = .failed(Self.message(forRemoteError: error))
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
            remotePanel.selectedItemIds = [item.id]
            return
        }
        updateRemotePath(item.path)
        await refreshRemote()
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
