import SwiftUI

@main
struct WetransApp: App {
    var body: some Scene {
        WindowGroup("wetrans") {
            ContentView()
                .frame(minWidth: 980, minHeight: 620)
        }
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}

