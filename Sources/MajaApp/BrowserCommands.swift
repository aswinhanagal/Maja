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
    let addBookmark: () -> Void
    let newTab: () -> Void
    let closeTab: () -> Bool
    let openFolder: () -> Void
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
        CommandGroup(replacing: .newItem) {
            Button("New Window") { openWindow(id: "browser") }
                .keyboardShortcut("n", modifiers: .command)
            Button("New Folder") { actions?.newFolder() }
                .keyboardShortcut("n", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("New Tab") { actions?.newTab() }
                .keyboardShortcut("t", modifiers: .command)
                .disabled(actions == nil)
        }
        CommandGroup(after: .newItem) {
            Button("Open Folder…") { actions?.openFolder() }
                .keyboardShortcut("o", modifiers: .command)
                .disabled(actions == nil)
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
            Button("Rename") { actions?.rename() }
                .keyboardShortcut(.return, modifiers: [])
                .disabled(actions?.hasSelection != true)
            Button("Duplicate") { actions?.duplicate() }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(actions == nil)
            Button("Move to Trash") { actions?.trash() }
                .keyboardShortcut(.delete, modifiers: .command)
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
        }
        CommandMenu("Bookmarks") {
            Button("Add Bookmark") { actions?.addBookmark() }
                .keyboardShortcut("d", modifiers: .command)
                .disabled(actions == nil)
        }
    }
}
