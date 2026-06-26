import SwiftUI
import wetrans

struct ContentView: View {
    @StateObject private var browserViewModel = MainBrowserViewModel()
    @State private var isShowingConnectHost = false

    var body: some View {
        MainBrowserView(viewModel: browserViewModel) {
            isShowingConnectHost = true
        }
        .sheet(isPresented: $isShowingConnectHost, onDismiss: reloadHosts) {
            ConnectHostDialogView()
        }
    }

    private func reloadHosts() {
        try? browserViewModel.loadHosts()
    }
}
