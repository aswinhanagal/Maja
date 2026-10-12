import SwiftUI

@main
struct MajaApp: App {
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

        Window("Maja Preferences", id: "preferences") {
            PreferencesView()
        }
        .windowResizability(.contentSize)
    }
}
