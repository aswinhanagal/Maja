import Foundation
import Observation
import AppKit
import UniformTypeIdentifiers
import MajaCoreFFI

struct DirectoryListing: Decodable, Sendable {
    let path: String
    let entries: [FileEntry]
    let error: String?
}

struct FileEntry: Decodable, Identifiable, Hashable, Sendable {
    let name: String
    let path: String
    let isDirectory: Bool
    let size: UInt64
    let modified: UInt64
    let isHidden: Bool
    var id: String { path }
}

struct Bookmark: Codable, Identifiable, Hashable, Sendable {
    let path: String
    let name: String
    var id: String { path }
    var url: URL { URL(fileURLWithPath: path) }
}

@MainActor
@Observable
final class BrowserModel {
    var currentURL: URL
    var entries: [FileEntry] = []
    var selectedEntryIDs: Set<String> = []
    var selectedEntry: FileEntry? {
        get { selectedEntries.first }
        set { selectedEntryIDs = newValue.map { [$0.id] } ?? [] }
    }
    var selectedEntries: [FileEntry] {
        visibleEntries.filter { selectedEntryIDs.contains($0.id) }
    }
    var errorMessage: String?
    var operationError: String?
    var isShowingNewFolder = false
    var newFolderName = ""
    var renameName = ""
    var renamingPath: String?
    var iconScale: Double = min(1.8, max(0.65, UserDefaults.standard.object(forKey: "maja.iconScale") as? Double ?? 1)) {
        didSet { UserDefaults.standard.set(iconScale, forKey: "maja.iconScale") }
    }
    var isLoading = false
    var isSearching = false
    var viewMode: ViewMode = ViewMode(rawValue: UserDefaults.standard.string(forKey: "maja.viewMode") ?? "List") ?? .list {
        didSet { UserDefaults.standard.set(viewMode.rawValue, forKey: "maja.viewMode") }
    }
    var showHiddenFiles = UserDefaults.standard.bool(forKey: "maja.showHiddenFiles") {
        didSet { UserDefaults.standard.set(showHiddenFiles, forKey: "maja.showHiddenFiles") }
    }
    var sortMode: SortMode = SortMode(rawValue: UserDefaults.standard.string(forKey: "maja.sortMode") ?? "Name") ?? .name {
        didSet { UserDefaults.standard.set(sortMode.rawValue, forKey: "maja.sortMode") }
    }
    var sortAscending = UserDefaults.standard.object(forKey: "maja.sortAscending") as? Bool ?? true {
        didSet { UserDefaults.standard.set(sortAscending, forKey: "maja.sortAscending") }
    }
    var searchText = ""
    var backStack: [URL] = []
    var forwardStack: [URL] = []
    var bookmarks: [Bookmark] = []
    var searchResults: [FileEntry]?
    @ObservationIgnored private var searchTask: Task<Void, Never>?
    @ObservationIgnored private var lastOpenedFolder: (path: String, time: Date)?

    init(at url: URL = FileManager.default.homeDirectoryForCurrentUser) {
        currentURL = url
        if let data = UserDefaults.standard.data(forKey: "maja.bookmarks"),
           let saved = try? JSONDecoder().decode([Bookmark].self, from: data) {
            bookmarks = saved
        }
        refresh()
    }

    var visibleEntries: [FileEntry] {
        let source = searchText.isEmpty ? entries : (searchResults ?? [])
        let filtered = source.filter { showHiddenFiles || !$0.isHidden }
        return filtered.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            let comparison: ComparisonResult
            switch sortMode {
            case .name: comparison = lhs.name.localizedStandardCompare(rhs.name)
            case .size: comparison = lhs.size == rhs.size ? lhs.name.localizedStandardCompare(rhs.name) : (lhs.size < rhs.size ? .orderedAscending : .orderedDescending)
            case .modified: comparison = lhs.modified == rhs.modified ? lhs.name.localizedStandardCompare(rhs.name) : (lhs.modified < rhs.modified ? .orderedAscending : .orderedDescending)
            case .kind:
                let lhsKind = URL(fileURLWithPath: lhs.name).pathExtension
                let rhsKind = URL(fileURLWithPath: rhs.name).pathExtension
                comparison = lhsKind.localizedStandardCompare(rhsKind)
            }
            return sortAscending ? comparison == .orderedAscending : comparison == .orderedDescending
        }
    }

    var canGoBack: Bool { !backStack.isEmpty }
    var canGoForward: Bool { !forwardStack.isEmpty }

    func navigate(to url: URL, recordHistory: Bool = true) {
        guard url.isFileURL else { return }
        if recordHistory && url.standardizedFileURL != currentURL.standardizedFileURL {
            backStack.append(currentURL)
            forwardStack.removeAll()
        }
        currentURL = url.standardizedFileURL
        selectedEntryIDs.removeAll()
        searchTask?.cancel()
        isSearching = false
        searchText = ""
        searchResults = nil
        refresh()
    }

    func refresh() {
        if !searchText.isEmpty {
            updateSearch(searchText)
            return
        }
        isLoading = true
        errorMessage = nil
        let directory = currentURL
        let directoryPath = directory.path
        Task { [weak self] in
            do {
                let listing = try await Task.detached(priority: .userInitiated) {
                    let data = try Self.runCore(arguments: ["list", directoryPath])
                    let listing = try JSONDecoder().decode(DirectoryListing.self, from: data)
                    if let error = listing.error {
                        throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                    }
                    return listing
                }.value
                guard let self, self.currentURL == directory else { return }
                self.entries = listing.entries
                self.isLoading = false
            } catch {
                guard let self, self.currentURL == directory else { return }
                self.entries = []
                self.errorMessage = error.localizedDescription
                self.isLoading = false
            }
        }
    }

    func loadDirectoryEntries(at directory: URL) async throws -> [FileEntry] {
        let directoryPath = directory.path
        return try await Task.detached(priority: .userInitiated) {
            let data = try Self.runCore(arguments: ["list", directoryPath])
            let listing = try JSONDecoder().decode(DirectoryListing.self, from: data)
            if let error = listing.error {
                throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
            }
            return listing.entries
        }.value
    }

    func updateSearch(_ query: String) {
        searchTask?.cancel()
        guard !query.isEmpty else {
            searchResults = nil
            isSearching = false
            return
        }
        let directory = currentURL
        searchResults = []
        isSearching = true
        searchTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: 250_000_000)
                let listing = try await Task.detached(priority: .userInitiated) {
                    let data = try Self.runCore(arguments: ["search", directory.path, query])
                    let result = try JSONDecoder().decode(DirectoryListing.self, from: data)
                    if let error = result.error {
                        throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                    }
                    return result
                }.value
                guard let self, self.currentURL == directory, self.searchText == query else { return }
                self.searchResults = listing.entries
                self.isSearching = false
            } catch {
                guard let self, !Task.isCancelled, self.currentURL == directory, self.searchText == query else { return }
                self.searchResults = []
                self.operationError = error.localizedDescription
                self.isSearching = false
            }
        }
    }

    func open(_ entry: FileEntry) {
        let url = URL(fileURLWithPath: entry.path)
        if url.pathExtension.caseInsensitiveCompare("app") == .orderedSame {
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
                guard let error else { return }
                Task { @MainActor in self?.operationError = error.localizedDescription }
            }
            return
        }
        if entry.isDirectory {
            let now = Date()
            if let lastOpenedFolder, lastOpenedFolder.path == entry.path,
               now.timeIntervalSince(lastOpenedFolder.time) < 0.35 { return }
            lastOpenedFolder = (entry.path, now)
            navigate(to: url)
        }
        else {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
            process.arguments = [entry.path]
            try? process.run()
        }
    }

    func goBack() {
        guard let destination = backStack.popLast() else { return }
        forwardStack.append(currentURL)
        navigate(to: destination, recordHistory: false)
    }

    func goForward() {
        guard let destination = forwardStack.popLast() else { return }
        backStack.append(currentURL)
        navigate(to: destination, recordHistory: false)
    }

    func goUp() {
        let parent = currentURL.deletingLastPathComponent()
        if parent != currentURL { navigate(to: parent) }
    }

    func openFolderPicker() {
        let panel = NSOpenPanel()
        panel.title = "Open Folder"
        panel.prompt = "Open"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL
        if panel.runModal() == .OK, let url = panel.url { navigate(to: url) }
    }

    func addCurrentBookmark() {
        let path = currentURL.path
        guard !bookmarks.contains(where: { $0.path == path }) else { return }
        bookmarks.append(Bookmark(path: path, name: currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : currentURL.lastPathComponent))
        saveBookmarks()
    }

    func removeBookmark(_ bookmark: Bookmark) {
        bookmarks.removeAll { $0.id == bookmark.id }
        saveBookmarks()
    }

    func createFolder(named name: String) {
        perform(["create-folder", currentURL.path, name])
    }

    func createNewDocument(asTextFile: Bool) {
        let stem = "Untitled"
        let suffix = asTextFile ? ".txt" : ""
        var name = stem + suffix
        var index = 2
        while FileManager.default.fileExists(atPath: currentURL.appending(path: name).path) {
            name = "\(stem) \(index)\(suffix)"
            index += 1
        }
        perform(["create-file", currentURL.path, name], selectName: name)
    }

    func renameSelected(to name: String) {
        guard let path = renamingPath ?? (selectedEntries.count == 1 ? selectedEntry?.path : nil) else { return }
        renameItem(at: path, to: name)
    }

    func selectAll() { selectedEntryIDs = Set(visibleEntries.map(\.id)) }

    func select(_ entry: FileEntry, extend: Bool = false) {
        if extend {
            if selectedEntryIDs.contains(entry.id) { selectedEntryIDs.remove(entry.id) }
            else { selectedEntryIDs.insert(entry.id) }
        } else { selectedEntryIDs = [entry.id] }
    }

    func selectPattern() {
        let alert = NSAlert()
        alert.messageText = "Select Items by Pattern"
        alert.informativeText = "Use * for any number of characters and ? for a single character."
        let input = NSTextField(string: "*")
        input.frame = NSRect(x: 0, y: 0, width: 240, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Select")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let escaped = NSRegularExpression.escapedPattern(for: input.stringValue)
            .replacingOccurrences(of: "\\*", with: ".*")
            .replacingOccurrences(of: "\\?", with: ".")
        guard let regex = try? NSRegularExpression(pattern: "^\(escaped)$", options: [.caseInsensitive]) else { return }
        selectedEntryIDs = Set(visibleEntries.filter {
            regex.firstMatch(in: $0.name, range: NSRange($0.name.startIndex..., in: $0.name)) != nil
        }.map(\.id))
    }

    func clearHistory() { backStack.removeAll(); forwardStack.removeAll() }

    func connectToServer(_ address: String) {
        let value = address.contains("://") ? address : "smb://\(address)"
        guard let url = URL(string: value), ["smb", "afp", "ftp", "https", "http"].contains(url.scheme?.lowercased() ?? "") else {
            operationError = "Enter a valid server address, such as smb://server/share."
            return
        }
        guard NSWorkspace.shared.open(url) else { operationError = "macOS couldn’t open this server address."; return }
    }

    func requestConnectToServer() {
        let alert = NSAlert()
        alert.messageText = "Connect to Server"
        alert.informativeText = "Enter a network address such as smb://server/share."
        let input = NSTextField(string: "smb://")
        input.frame = NSRect(x: 0, y: 0, width: 280, height: 24)
        alert.accessoryView = input
        alert.addButton(withTitle: "Connect")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn { connectToServer(input.stringValue) }
    }

    var hasTrashItems: Bool {
        let trashPath = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash").path
        return (try? FileManager.default.contentsOfDirectory(atPath: trashPath).isEmpty) == false
    }

    func emptyTrash() {
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Empty Trash?"
        alert.informativeText = "Items in the Trash will be permanently deleted. This can’t be undone."
        alert.addButton(withTitle: "Empty Trash")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        let trash = URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash")
        do {
            for name in try FileManager.default.contentsOfDirectory(atPath: trash.path) {
                try FileManager.default.removeItem(at: trash.appending(path: name))
            }
        } catch { operationError = error.localizedDescription }
    }

    func duplicateSelected() {
        let commands = selectedEntries.map { ["duplicate", $0.path] }
        if !commands.isEmpty { performBatch(commands) }
    }

    func makeLinkSelected() {
        let commands = selectedEntries.map { entry -> [String] in
            let base = "\(entry.name) alias"
            var name = base
            var suffix = 2
            while FileManager.default.fileExists(atPath: currentURL.appending(path: name).path) {
                name = "\(base) \(suffix)"
                suffix += 1
            }
            return ["link", entry.path, currentURL.appending(path: name).path]
        }
        if !commands.isEmpty { performBatch(commands) }
    }

    func chooseTransferDestination(move: Bool) {
        guard let selectedEntry else { return }
        let panel = NSOpenPanel()
        panel.title = move ? "Move To" : "Copy To"
        panel.prompt = move ? "Move" : "Copy"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.directoryURL = currentURL
        guard panel.runModal() == .OK, let destination = panel.url else { return }
        let target = destination.appending(path: selectedEntry.name)
        guard target.standardizedFileURL != URL(fileURLWithPath: selectedEntry.path).standardizedFileURL else { return }
        perform([move ? "move" : "copy", selectedEntry.path, target.path])
    }

    @discardableResult
    func acceptDrop(_ sources: [URL], on target: FileEntry? = nil) -> Bool {
        let destinationDirectory: URL
        if let target {
            guard target.isDirectory else { return false }
            destinationDirectory = URL(fileURLWithPath: target.path, isDirectory: true)
        } else {
            destinationDirectory = currentURL
        }

        let destinationPath = destinationDirectory.standardizedFileURL.path
        let commands = sources.compactMap { source -> [String]? in
            guard source.isFileURL else { return nil }
            let sourceURL = source.standardizedFileURL
            guard sourceURL.deletingLastPathComponent() != destinationDirectory.standardizedFileURL else { return nil }
            let destination = destinationDirectory.appending(path: sourceURL.lastPathComponent).standardizedFileURL
            guard sourceURL.path != destination.path else { return nil }
            var isDirectory: ObjCBool = false
            _ = FileManager.default.fileExists(atPath: sourceURL.path, isDirectory: &isDirectory)
            if isDirectory.boolValue && destinationPath.hasPrefix(sourceURL.path + "/") { return nil }
            return ["move", sourceURL.path, destination.path]
        }
        guard !commands.isEmpty else { return false }
        performBatch(commands)
        return true
    }

    func openInTerminal(at url: URL? = nil) {
        let directory = url ?? currentURL
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["-a", "Terminal", directory.path]
        do { try process.run() } catch { operationError = error.localizedDescription }
    }

    func openWithOtherApplication(_ entry: FileEntry) {
        let panel = NSOpenPanel()
        panel.title = "Open With Other Application"
        panel.prompt = "Open"
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.applicationBundle]
        guard panel.runModal() == .OK, let applicationURL = panel.url else { return }
        NSWorkspace.shared.open([URL(fileURLWithPath: entry.path)], withApplicationAt: applicationURL, configuration: NSWorkspace.OpenConfiguration())
    }

    func defaultApplicationName(for entry: FileEntry) -> String {
        let fileURL = URL(fileURLWithPath: entry.path)
        guard let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: fileURL),
              let bundle = Bundle(url: applicationURL) else { return "Default Application" }
        return (bundle.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String)
            ?? (bundle.object(forInfoDictionaryKey: "CFBundleName") as? String)
            ?? applicationURL.deletingPathExtension().lastPathComponent
    }

    func zoomIn() { iconScale = min(1.8, iconScale + 0.15) }
    func zoomOut() { iconScale = max(0.65, iconScale - 0.15) }
    func resetZoom() { iconScale = 1 }

    func requestNewFolder() {
        newFolderName = ""
        isShowingNewFolder = true
    }

    func requestRename() {
        guard selectedEntries.count == 1, let selectedEntry else { return }
        renameName = selectedEntry.name
        renamingPath = selectedEntry.path
    }

    private func renameItem(at path: String, to proposedName: String) {
        let name = proposedName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, name != ".", name != "..", !name.contains("/") else {
            operationError = "Enter a valid file name. Names can’t be empty or contain a slash."
            return
        }
        let source = URL(fileURLWithPath: path)
        guard name != source.lastPathComponent else { cancelRename(); return }
        let destination = source.deletingLastPathComponent().appending(path: name)
        let caseOnlyRename = destination.path.compare(source.path, options: [.caseInsensitive]) == .orderedSame
        if destination.standardizedFileURL != source.standardizedFileURL, !caseOnlyRename,
           FileManager.default.fileExists(atPath: destination.path) {
            operationError = "A file or folder named ‘\(name)’ already exists in this location."
            return
        }
        let directory = currentURL
        Task { [weak self] in
            do {
                let listing = try await Task.detached(priority: .userInitiated) {
                    _ = try Self.runCore(arguments: ["rename", path, name])
                    let data = try Self.runCore(arguments: ["list", directory.path])
                    let listing = try JSONDecoder().decode(DirectoryListing.self, from: data)
                    if let error = listing.error {
                        throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: error])
                    }
                    return listing
                }.value
                guard let self, self.currentURL == directory else { return }
                self.entries = listing.entries
                self.selectedEntry = listing.entries.first { $0.name == name }
                self.renamingPath = nil
            } catch {
                guard let self else { return }
                self.renamingPath = path
                self.operationError = error.localizedDescription
            }
        }
    }

    func cancelRename() {
        renamingPath = nil
    }

    func moveSelectedToTrash() {
        guard !selectedEntries.isEmpty else { return }
        do {
            for entry in selectedEntries {
                var resultingURL: NSURL?
                try FileManager.default.trashItem(at: URL(fileURLWithPath: entry.path), resultingItemURL: &resultingURL)
            }
            selectedEntryIDs.removeAll()
            refresh()
        } catch { operationError = error.localizedDescription }
    }

    func copySelectedToClipboard(cut: Bool = false) {
        let selection = selectedEntries
        guard !selection.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects(selection.map { URL(fileURLWithPath: $0.path) as NSURL })
        if cut {
            pasteboard.setString("true", forType: NSPasteboard.PasteboardType("dev.maja.cut-files"))
        }
    }

    func pasteClipboard() {
        let pasteboard = NSPasteboard.general
        guard let urls = pasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] else { return }
        let isCut = pasteboard.string(forType: NSPasteboard.PasteboardType("dev.maja.cut-files")) == "true"
        var commands: [[String]] = []
        for source in urls {
            guard source.standardizedFileURL.deletingLastPathComponent() != currentURL.standardizedFileURL else { continue }
            let destination = currentURL.appending(path: source.lastPathComponent)
            if source.standardizedFileURL == destination.standardizedFileURL { continue }
            commands.append([isCut ? "move" : "copy", source.path, destination.path])
        }
        guard !commands.isEmpty else { return }
        performBatch(commands)
        if isCut { pasteboard.setString("false", forType: NSPasteboard.PasteboardType("dev.maja.cut-files")) }
    }

    private func perform(_ arguments: [String], selectName: String? = nil) {
        performBatch([arguments], selectName: selectName)
    }

    private func performBatch(_ commands: [[String]], selectName: String? = nil) {
        let directory = currentURL
        Task { [weak self] in
            do {
                try await Task.detached(priority: .userInitiated) {
                    for arguments in commands { _ = try Self.runCore(arguments: arguments) }
                }.value
                guard let self, self.currentURL == directory else { return }
                self.refresh()
                if let selectName {
                    self.selectedEntry = self.entries.first { $0.name == selectName }
                }
            } catch {
                guard let self else { return }
                self.operationError = error.localizedDescription
            }
        }
    }

    private func saveBookmarks() {
        guard let data = try? JSONEncoder().encode(bookmarks) else { return }
        UserDefaults.standard.set(data, forKey: "maja.bookmarks")
    }

    nonisolated private static func runCore(arguments: [String]) throws -> Data {
        guard let command = arguments.first else {
            throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing file operation."])
        }
        if command == "list" {
            guard arguments.count > 1 else {
                throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing folder path."])
            }
            guard let pointer = arguments[1].withCString({ maja_list_json($0) }) else {
                throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Rust file core returned no result."])
            }
            defer { maja_string_free(pointer) }
            return Data(String(cString: pointer).utf8)
        }
        if command == "search" {
            guard arguments.count > 2 else {
                throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: "Missing search query."])
            }
            let pointer = arguments[1].withCString { pathPointer in
                arguments[2].withCString { queryPointer in
                    maja_search_json(pathPointer, queryPointer)
                }
            }
            guard let pointer else {
                throw NSError(domain: "Maja", code: 1, userInfo: [NSLocalizedDescriptionKey: "The Rust file core returned no search results."])
            }
            defer { maja_string_free(pointer) }
            return Data(String(cString: pointer).utf8)
        }
        let first = arguments.count > 1 ? arguments[1] : nil
        let second = arguments.count > 2 ? arguments[2] : nil
        let errorPointer = command.withCString { commandPointer in
            if let first, let second {
                return first.withCString { firstPointer in
                    second.withCString { secondPointer in
                        maja_run_operation(commandPointer, firstPointer, secondPointer)
                    }
                }
            } else if let first {
                return first.withCString { firstPointer in
                    maja_run_operation(commandPointer, firstPointer, nil)
                }
            } else {
                return maja_run_operation(commandPointer, nil, nil)
            }
        }
        guard let errorPointer else { return Data() }
        defer { maja_string_free(errorPointer) }
        throw NSError(domain: "Maja", code: 1,
                      userInfo: [NSLocalizedDescriptionKey: String(cString: errorPointer)])
    }
}

enum ViewMode: String, CaseIterable, Identifiable {
    case icons = "Icons"
    case list = "List"
    case compact = "Compact"
    var id: String { rawValue }
    var symbol: String {
        switch self { case .icons: "square.grid.2x2"; case .list: "list.bullet"; case .compact: "rectangle.grid.1x2" }
    }
}

enum SortMode: String, CaseIterable, Identifiable {
    case name = "Name"
    case kind = "Kind"
    case size = "Size"
    case modified = "Modified"
    var id: String { rawValue }
}
