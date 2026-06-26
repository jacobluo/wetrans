import SwiftUI

@main
struct WetransApp: App {
    var body: some Scene {
        WindowGroup("wetrans") {
            ContentView()
                .frame(minWidth: 1180, minHeight: 720)
        }
        .defaultSize(width: 1320, height: 860)
        .commands {
            CommandGroup(replacing: .newItem) {}
        }
    }
}
