import AppKit
import SwiftUI

@main
struct WetransApp: App {
    @NSApplicationDelegateAdaptor(E2EWindowDelegate.self) private var e2eWindowDelegate

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

final class E2EWindowDelegate: NSObject, NSApplicationDelegate {
    private var window: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        guard ProcessInfo.processInfo.environment["WETRANS_E2E_FORCE_WINDOW"] == "1" else {
            return
        }

        try? "forcing window\n".write(
            toFile: "/tmp/wetrans-e2e-window.log",
            atomically: true,
            encoding: .utf8
        )
        NSApplication.shared.setActivationPolicy(.regular)
        let visibleWindows = NSApplication.shared.windows.filter { $0.isVisible }
        guard visibleWindows.isEmpty else {
            return
        }

        let hostingController = NSHostingController(
            rootView: ContentView().frame(minWidth: 1180, minHeight: 720)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1320, height: 860),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.contentViewController = hostingController
        window.title = "wetrans"
        window.isReleasedWhenClosed = false
        window.center()
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate()
        self.window = window
        try? "forcing window count \(NSApplication.shared.windows.count)\n".write(
            toFile: "/tmp/wetrans-e2e-window.log",
            atomically: true,
            encoding: .utf8
        )
    }
}
