import SwiftUI
import wetrans

struct ContentView: View {
    @StateObject private var browserViewModel = MainBrowserViewModel()
    @State private var isShowingConnectHost = false
    private let hostCatalog = FileHostCatalog(applicationSupportDirectory: FileManager.wetransApplicationSupportDirectory)
    private let credentialStore = KeychainCredentialStore()

    var body: some View {
        MainBrowserView(viewModel: browserViewModel) {
            isShowingConnectHost = true
        }
        .sheet(isPresented: $isShowingConnectHost, onDismiss: reloadHosts) {
            ConnectHostSheetView(
                catalog: hostCatalog,
                credentialStore: credentialStore
            ) { savedHost in
                reloadHosts()
                browserViewModel.select(hostId: savedHost.id)
                isShowingConnectHost = false
            }
        }
    }

    private func reloadHosts() {
        try? browserViewModel.loadHosts()
    }
}
