import SwiftUI
import wetrans

struct ContentView: View {
    @StateObject private var appState = AppState()
    @StateObject private var browserViewModel = MainBrowserViewModel()
    private let hostCatalog = FileHostCatalog(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory)
    private let credentialStore = KeychainCredentialStore()
    private let trustedHostStore = FileTrustedHostStore(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory)

    var body: some View {
        MainBrowserView(viewModel: browserViewModel) {
            appState.showConnectHost()
        }
        .sheet(isPresented: $appState.isShowingConnectHost, onDismiss: reloadHosts) {
            ConnectHostSheetView(
                catalog: hostCatalog,
                credentialStore: credentialStore,
                trustedHostStore: trustedHostStore,
                hostSessionCleaner: browserViewModel
            ) { savedHost in
                reloadHosts()
                appState.selectHost(savedHost.id)
                browserViewModel.select(hostId: savedHost.id)
                appState.dismissConnectHost()
            }
        }
    }

    private func reloadHosts() {
        try? browserViewModel.loadHosts()
    }
}
