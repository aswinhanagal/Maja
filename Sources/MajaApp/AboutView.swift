import AppKit
import SwiftUI

struct PreferencesView: View {
    @AppStorage("maja.showHiddenFiles") private var showHiddenFiles = false
    @AppStorage("maja.viewMode") private var defaultView = "List"
    @AppStorage("maja.sortMode") private var sortMode = "Name"
    @AppStorage("maja.sortAscending") private var sortAscending = true

    var body: some View {
        Form {
            Section("When opening a folder") {
                Picker("Default view", selection: $defaultView) {
                    ForEach(ViewMode.allCases) { mode in Text(mode.rawValue).tag(mode.rawValue) }
                }
                Picker("Sort by", selection: $sortMode) {
                    ForEach(SortMode.allCases) { mode in Text(mode.rawValue).tag(mode.rawValue) }
                }
                Toggle("Sort in ascending order", isOn: $sortAscending)
                Toggle("Show hidden files", isOn: $showHiddenFiles)
            }
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(width: 390)
    }
}

private enum AboutPage: String, CaseIterable, Identifiable {
    case about = "About"
    case credits = "Credits"
    var id: String { rawValue }
}

struct AboutView: View {
    @State private var page: AboutPage = .about

    private var appIcon: NSImage {
        if let url = Bundle.main.url(forResource: "Maja", withExtension: "icns"),
           let image = NSImage(contentsOf: url) {
            return image
        }
        return NSImage(systemSymbolName: "folder", accessibilityDescription: "Maja")!
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("About section", selection: $page) {
                ForEach(AboutPage.allCases) { page in
                    Text(page.rawValue).tag(page)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 24)
            .padding(.top, 18)
            .padding(.bottom, 14)

            Divider()

            Group {
                switch page {
                case .about: aboutPage
                case .credits: creditsPage
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(24)
        }
        .frame(width: 390, height: 440)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var aboutPage: some View {
        VStack(spacing: 10) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 88, height: 88)
                .padding(.bottom, 2)

            Text("Maja").font(.title2.weight(.semibold))
            Text("0.1.2").foregroundStyle(.secondary)
            Text("A native macOS file manager inspired by Caja.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.top, 4)

            Text("Author: Aswin Hanagal")
                .font(.callout)
                .padding(.top, 4)

            Spacer(minLength: 4)
            Divider()
            Text("Copyright © 2026 Aswin Hanagal")
                .font(.caption)
                .foregroundStyle(.secondary)
            Text("This program comes with absolutely no warranty.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Link("GNU General Public License, version 2 or later",
                 destination: URL(string: "https://www.gnu.org/licenses/old-licenses/gpl-2.0.html")!)
                .font(.caption)
        }
        .frame(maxWidth: 300)
    }

    private var creditsPage: some View {
        VStack(spacing: 14) {
            Image(nsImage: appIcon)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 64, height: 64)
            Text("Maja").font(.title2.weight(.semibold))
            Text("Author").font(.caption).foregroundStyle(.secondary)
            Text("Aswin Hanagal").font(.headline)
            Divider().padding(.vertical, 4)
            Text("Inspired by Caja, the MATE file manager.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text("Built with Rust, SwiftUI, AppKit, and Codex.")
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: 300)
    }
}
