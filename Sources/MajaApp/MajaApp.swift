import SwiftUI
import AppKit

@main
struct MajaApp: App {
    init() {
        if let iconURL = Bundle.main.url(forResource: "Maja", withExtension: "icns"),
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
    }

    var body: some Scene {
        WindowGroup("Maja", id: "browser") {
            BrowserWindow(model: BrowserModel())
                .frame(minWidth: 860, minHeight: 560)
        }
        .commands { MajaCommands() }

        Window("About Maja", id: "about") {
            AboutView()
        }
        .windowResizability(.contentSize)
    }
}
