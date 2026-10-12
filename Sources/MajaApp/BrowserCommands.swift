import SwiftUI

@MainActor
struct BrowserCommandActions {
    let back: () -> Void
    let forward: () -> Void
    let up: () -> Void
    let home: () -> Void
    let refresh: () -> Void
    let newFolder: () -> Void
    let rename: () -> Void
    let duplicate: () -> Void
    let trash: () -> Void
    let copy: () -> Void
    let cut: () -> Void
    let paste: () -> Void
    let hasSelection: Bool
    let hasSingleSelection: Bool
    let selectAll: () -> Void
    let selectPattern: () -> Void
    let clearHistory: () -> Void
    let connectToServer: () -> Void
    let properties: () -> Void
    let emptyTrash: () -> Void
    let hasTrashItems: Bool
    let toggleSidebar: () -> Void
    let toggleMainToolbar: () -> Void
    let toggleLocationBar: () -> Void
    let toggleStatusBar: () -> Void
    let sidebarShown: Bool
    let mainToolbarShown: Bool
    let locationBarShown: Bool
    let statusBarShown: Bool
    let resetView: () -> Void
    let addBookmark: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Bool
    let openFolder: () -> Void
    let createEmptyFile: () -> Void
    let createTextFile: () -> Void
    let zoomIn: () -> Void
    let zoomOut: () -> Void
    let resetZoom: () -> Void
    let makeLink: () -> Void
    let computer: () -> Void
    let templates: () -> Void
    let trashFolder: () -> Void
    let editLocation: () -> Void
    let focusSearch: () -> Void
}

private struct BrowserCommandActionsKey: FocusedValueKey {
    typealias Value = BrowserCommandActions
}

extension FocusedValues {
    var majaBrowserActions: BrowserCommandActions? {
        get { self[BrowserCommandActionsKey.self] }
        set { self[BrowserCommandActionsKey.self] = newValue }
    }
}

struct MajaCommands: Commands {
    @FocusedValue(\.majaBrowserActions) private var actions
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About Maja") { openWindow(id: "about") }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { openWindow(id: "preferences") }
                .keyboardShortcut(",", modifiers: .command)
        }
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Folder") { actions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions == nil)
            Menu("Create Document") {
                Button("Empty File") { actions?.createEmptyFile() }
                Button("Text File") { actions?.createTextFile() }
            }
            .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
            Button("Connect to Server…") { actions?.connectToServer() }
                .keyboardShortcut("k", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Properties…") { actions?.properties() }
                .keyboardShortcut(.return, modifiers: [.option])
                .disabled(actions == nil)
            Button("Empty Trash…", role: .destructive) { actions?.emptyTrash() }
                .disabled(actions?.hasTrashItems != true)
        }
        CommandGroup(after: .windowArrangement) {
            Button("Close Tab") {
                if actions?.closeTab() == false { dismissWindow() }
            }
            .keyboardShortcut("w", modifiers: .command)
            .disabled(actions == nil)
        }
        CommandGroup(after: .pasteboard) {
            Divider()
            Button("Copy Selected File") { actions?.copy() }
                .disabled(actions?.hasSelection != true)
            Button("Cut Selected File") { actions?.cut() }
                .disabled(actions?.hasSelection != true)
            Button("Paste File") { actions?.paste() }
                .disabled(actions == nil)
            Divider()
            Button("Select All") { actions?.selectAll() }
                .keyboardShortcut("a", modifiers: .command)
                .disabled(actions == nil)
            Button("Select by Pattern…") { actions?.selectPattern() }
                .keyboardShortcut("s", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Divider()
            Button("Rename") { actions?.rename() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(actions?.hasSingleSelection != true)
            Button("Duplicate") { actions?.duplicate() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(actions?.hasSelection != true)
            Button("Make Link") { actions?.makeLink() }
                .keyboardShortcut("m", modifiers: [.command, .shift])
                .disabled(actions?.hasSelection != true)
            Button("Move to Trash") { actions?.trash() }
                .keyboardShortcut(.delete, modifiers: .command)
                .disabled(actions?.hasSelection != true)
        }
        CommandGroup(after: .toolbar) {
            Button { actions?.toggleMainToolbar() } label: {
                if actions?.mainToolbarShown == true { Label("Main Toolbar", systemImage: "checkmark") }
                else { Text("Main Toolbar") }
            }
                .disabled(actions == nil)
            Button { actions?.toggleSidebar() } label: {
                if actions?.sidebarShown == true { Label("Side Pane", systemImage: "checkmark") }
                else { Text("Side Pane") }
            }
                .keyboardShortcut("f", modifiers: [])
                .disabled(actions == nil)
            Button { actions?.toggleLocationBar() } label: {
                if actions?.locationBarShown == true { Label("Location Bar", systemImage: "checkmark") }
                else { Text("Location Bar") }
            }
                .disabled(actions == nil)
            Button { actions?.toggleStatusBar() } label: {
                if actions?.statusBarShown == true { Label("Status Bar", systemImage: "checkmark") }
                else { Text("Status Bar") }
            }
                .disabled(actions == nil)
            Divider()
            Button("Reset View to Defaults") { actions?.resetView() }
                .disabled(actions == nil)
            Divider()
            Button("Zoom In") { actions?.zoomIn() }
                .keyboardShortcut("+", modifiers: .command)
                .disabled(actions == nil)
            Button("Zoom Out") { actions?.zoomOut() }
                .keyboardShortcut("-", modifiers: .command)
                .disabled(actions == nil)
            Button("Normal Size") { actions?.resetZoom() }
                .keyboardShortcut("0", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandMenu("Go") {
            Button("Back") { actions?.back() }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(actions == nil)
            Button("Forward") { actions?.forward() }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(actions == nil)
            Button("Enclosing Folder") { actions?.up() }
                .keyboardShortcut("↑", modifiers: [.command, .option])
                .disabled(actions == nil)
            Button("Home") { actions?.home() }
                .keyboardShortcut("h", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Reload") { actions?.refresh() }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(actions == nil)
            Divider()
            Button("Computer") { actions?.computer() }.disabled(actions == nil)
            Button("Templates") { actions?.templates() }.disabled(actions == nil)
            Button("Trash") { actions?.trashFolder() }.disabled(actions == nil)
            Button("Location…") { actions?.editLocation() }
                .keyboardShortcut("l", modifiers: .command)
                .disabled(actions == nil)
            Button("Search") { actions?.focusSearch() }
                .keyboardShortcut("f", modifiers: .command)
                .disabled(actions == nil)
            Button("Connect to Server…") { actions?.connectToServer() }.disabled(actions == nil)
            Divider()
            Button("Clear History") { actions?.clearHistory() }
                .disabled(actions == nil)
        }
        CommandMenu("Bookmarks") {
            Button("Add Bookmark") { actions?.addBookmark() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}
