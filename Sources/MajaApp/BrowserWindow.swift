import SwiftUI
import UniformTypeIdentifiers

struct BrowserWindow: View {
    @State private var tabs: [BrowserTab]
    @State private var selectedTabID: UUID

    init(model: BrowserModel) {
        let first = BrowserTab(model: model)
        _tabs = State(initialValue: [first])
        _selectedTabID = State(initialValue: first.id)
    }

    private var activeTab: BrowserTab { tabs.first(where: { $0.id == selectedTabID }) ?? tabs[0] }

    var body: some View {
        VStack(spacing: 0) {
            if tabs.count > 1 { tabStrip }
            BrowserPane(model: activeTab.model, newTab: createTab, closeTab: closeSelectedTab)
                .id(selectedTabID)
        }
    }

    private var tabStrip: some View {
        HStack(spacing: 2) {
            ForEach(tabs) { tab in
                HStack(spacing: 6) {
                    Button {
                        selectedTabID = tab.id
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: "folder")
                            Text(tab.title).lineLimit(1)
                        }
                        .frame(maxWidth: 180, minHeight: 28)
                        .padding(.horizontal, 8)
                        .background(selectedTabID == tab.id ? Color(nsColor: .controlBackgroundColor) : .clear,
                                    in: RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                    Button { closeTab(tab.id) } label: { Image(systemName: "xmark").font(.caption2) }
                        .buttonStyle(.plain).help("Close Tab")
                }
            }
            Button { createTab() } label: { Image(systemName: "plus") }
                .buttonStyle(.plain).padding(.leading, 4).help("New Tab")
            Spacer()
        }
        .padding(.horizontal, 8).padding(.vertical, 4)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private func createTab() {
        let tab = BrowserTab(model: BrowserModel(at: activeTab.model.currentURL))
        tabs.append(tab)
        selectedTabID = tab.id
    }

    private func closeTab(_ id: UUID) {
        guard tabs.count > 1, let index = tabs.firstIndex(where: { $0.id == id }) else { return }
        tabs.remove(at: index)
        if selectedTabID == id { selectedTabID = tabs[min(index, tabs.count - 1)].id }
    }

    private func closeSelectedTab() -> Bool {
        guard tabs.count > 1 else { return false }
        closeTab(selectedTabID)
        return true
    }
}

@MainActor
private struct BrowserTab: Identifiable {
    let id = UUID()
    let model: BrowserModel
    var title: String { model.currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : model.currentURL.lastPathComponent }
}

private struct FileTreeRow: Identifiable {
    let entry: FileEntry
    let depth: Int
    var id: String { entry.path }
}

private struct BrowserPane: View {
    @Bindable var model: BrowserModel
    let newTab: () -> Void
    let closeTab: () -> Bool
    @State private var locationText = ""
    @State private var isEditingLocation = false
    @State private var showSidebar = true
    @State private var showMainToolbar = true
    @State private var showLocationBar = true
    @State private var showStatusBar = true
    @State private var propertiesPath: String?
    @State private var expandedFolderPaths: Set<String> = []
    @State private var folderChildren: [String: [FileEntry]] = [:]
    @State private var foldersLoading: Set<String> = []
    @FocusState private var locationFieldFocused: Bool
    @FocusState private var searchFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            if showMainToolbar || showLocationBar { toolbar }
            Divider()
            HSplitView {
                if showSidebar {
                    PlacesSidebar(model: model)
                        .frame(minWidth: 126, idealWidth: 210, maxWidth: 210)
                }
                content
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            if showStatusBar {
                HStack(spacing: 6) {
                    Text(statusSummary)
                    Spacer()
                    Text(model.currentURL.path).lineLimit(1).truncationMode(.middle)
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .sheet(isPresented: Binding(get: { propertiesPath != nil }, set: { if !$0 { propertiesPath = nil } })) {
            if let propertiesPath { FilePropertiesView(path: propertiesPath) }
        }
        .onAppear { locationText = model.currentURL.path }
        .onChange(of: model.currentURL) { _, url in locationText = url.path }
        .alert("Couldn’t Complete Operation", isPresented: Binding(
            get: { model.operationError != nil },
            set: { if !$0 { model.operationError = nil } }
        )) {
            Button("OK", role: .cancel) { model.operationError = nil }
        } message: {
            Text(model.operationError ?? "")
        }
        .focusedSceneValue(\.majaBrowserActions, BrowserCommandActions(
            back: model.goBack,
            forward: model.goForward,
            up: model.goUp,
            home: { model.navigate(to: FileManager.default.homeDirectoryForCurrentUser) },
            refresh: model.refresh,
            newFolder: model.requestNewFolder,
            rename: model.requestRename,
            duplicate: model.duplicateSelected,
            trash: model.moveSelectedToTrash,
            copy: { model.copySelectedToClipboard() },
            cut: { model.copySelectedToClipboard(cut: true) },
            paste: model.pasteClipboard,
            hasSelection: !model.selectedEntryIDs.isEmpty,
            hasSingleSelection: model.selectedEntryIDs.count == 1,
            selectAll: model.selectAll,
            selectPattern: model.selectPattern,
            clearHistory: model.clearHistory,
            connectToServer: model.requestConnectToServer,
            properties: { propertiesPath = model.currentURL.path },
            emptyTrash: model.emptyTrash,
            hasTrashItems: model.hasTrashItems,
            toggleSidebar: { showSidebar.toggle() },
            toggleMainToolbar: { showMainToolbar.toggle() },
            toggleLocationBar: { showLocationBar.toggle() },
            toggleStatusBar: { showStatusBar.toggle() },
            sidebarShown: showSidebar,
            mainToolbarShown: showMainToolbar,
            locationBarShown: showLocationBar,
            statusBarShown: showStatusBar,
            resetView: {
                model.resetZoom()
                model.viewMode = .icons
                model.sortMode = .name
                model.sortAscending = true
                model.showHiddenFiles = false
                showSidebar = true
                showMainToolbar = true
                showLocationBar = true
                showStatusBar = true
            },
            addBookmark: model.addCurrentBookmark,
            newTab: newTab,
            closeTab: closeTab,
            openFolder: model.openFolderPicker,
            createEmptyFile: { model.createNewDocument(asTextFile: false) },
            createTextFile: { model.createNewDocument(asTextFile: true) },
            zoomIn: model.zoomIn,
            zoomOut: model.zoomOut,
            resetZoom: model.resetZoom,
            makeLink: model.makeLinkSelected,
            computer: { model.navigate(to: URL(fileURLWithPath: "/")) },
            templates: { model.navigate(to: FileManager.default.homeDirectoryForCurrentUser.appending(path: "Templates")) },
            trashFolder: { model.navigate(to: URL(fileURLWithPath: NSHomeDirectory()).appending(path: ".Trash")) },
            editLocation: { isEditingLocation = true; locationFieldFocused = true },
            focusSearch: { searchFieldFocused = true }
        ))
    }

    private var statusSummary: String {
        let selection = model.selectedEntries
        if !selection.isEmpty {
            let files = selection.filter { !$0.isDirectory }
            let folders = selection.filter(\.isDirectory).count
            let size = files.reduce(UInt64(0)) { $0 + $1.size }
            var details = ["\(selection.count) selected"]
            if !files.isEmpty {
                details.append("\(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)) in \(files.count) files")
            }
            if folders > 0 { details.append("\(folders) folders") }
            return details.joined(separator: " · ")
        }

        let attributes = try? FileManager.default.attributesOfFileSystem(forPath: model.currentURL.path)
        if let free = attributes?[.systemFreeSize] as? NSNumber {
            return "\(model.visibleEntries.count) items · Free space: \(ByteCountFormatter.string(fromByteCount: free.int64Value, countStyle: .file))"
        }
        return "\(model.visibleEntries.count) items"
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            if showMainToolbar {
              HStack(spacing: 10) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack).help("Back")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward).help("Forward")
                Button { model.goUp() } label: { Image(systemName: "arrow.up") }.help("Enclosing Folder")
                Button { model.navigate(to: FileManager.default.homeDirectoryForCurrentUser) } label: { Image(systemName: "house") }.help("Home")
                Button { model.navigate(to: URL(fileURLWithPath: "/")) } label: { Image(systemName: "desktopcomputer") }
                    .help("Computer")
                Button { model.refresh() } label: { Image(systemName: "arrow.clockwise") }.help("Reload")
                Divider().frame(height: 22)
                Button { showSidebar.toggle() } label: { Image(systemName: "sidebar.left") }.help("Show or Hide Sidebar")
                Button { model.requestNewFolder() } label: { Image(systemName: "folder.badge.plus") }.help("New Folder")
                Button { newTab() } label: { Image(systemName: "plus.square.on.square") }.help("New Tab")
                Spacer(minLength: 12)
                Menu {
                    Toggle("Show Hidden Files", isOn: $model.showHiddenFiles)
                    Toggle("Sort Ascending", isOn: $model.sortAscending)
                    Divider()
                    Picker("Sort By", selection: $model.sortMode) {
                        ForEach(SortMode.allCases) { mode in Text(mode.rawValue).tag(mode) }
                    }
                    Divider()
                    Button("Add Bookmark") { model.addCurrentBookmark() }
                    Button("Paste") { model.pasteClipboard() }
                } label: { Image(systemName: "ellipsis.circle") }.help("More")
                Button { model.zoomOut() } label: { Image(systemName: "minus.magnifyingglass") }
                    .disabled(model.iconScale <= 0.65).help("Zoom Out")
                Button { model.resetZoom() } label: {
                    Text("\(Int(model.iconScale * 100))%")
                        .monospacedDigit()
                        .frame(minWidth: 38)
                }
                .help("Reset Zoom")
                Button { model.zoomIn() } label: { Image(systemName: "plus.magnifyingglass") }
                    .disabled(model.iconScale >= 1.8).help("Zoom In")
                Picker("View", selection: $model.viewMode) {
                    ForEach(ViewMode.allCases) { mode in
                        Label(mode.rawValue, systemImage: mode.symbol).tag(mode)
                    }
                }
                .pickerStyle(.segmented).labelsHidden().frame(width: 132)
            }
              .buttonStyle(.borderless)
              .padding(.horizontal, 12).padding(.vertical, 7)
              Divider()
            }
            if showLocationBar {
              HStack(spacing: 5) {
                if isEditingLocation {
                    Image(systemName: "folder").foregroundStyle(.secondary)
                    TextField("Location", text: $locationText)
                        .textFieldStyle(.plain)
                        .focused($locationFieldFocused)
                        .onSubmit { navigateToTypedLocation() }
                    Button("Go") { navigateToTypedLocation() }
                        .keyboardShortcut(.return, modifiers: [])
                        .buttonStyle(.borderless)
                } else {
                    ForEach(Array(breadcrumbs.enumerated()), id: \.offset) { index, crumb in
                        if index > 0 { Image(systemName: "chevron.right").font(.caption2).foregroundStyle(.tertiary) }
                        Button(crumb.title) { model.navigate(to: crumb.url) }
                            .buttonStyle(.borderless)
                            .foregroundStyle(index == breadcrumbs.count - 1 ? Color.primary : Color.secondary)
                    }
                }
                Spacer(minLength: 4)
                Button {
                    isEditingLocation.toggle()
                    if isEditingLocation { locationFieldFocused = true }
                } label: { Image(systemName: isEditingLocation ? "checkmark" : "pencil") }
                    .buttonStyle(.borderless).help(isEditingLocation ? "Done Editing Location" : "Edit Location")
            }
            .padding(.horizontal, 12).padding(.vertical, 6)
            }
        }
        .alert("New Folder", isPresented: $model.isShowingNewFolder) {
            TextField("Name", text: $model.newFolderName)
            Button("Create") { model.createFolder(named: model.newFolderName) }
            Button("Cancel", role: .cancel) { }
        } message: { Text("Create a folder in this location.") }
    }

    private var breadcrumbs: [Breadcrumb] {
        let components = model.currentURL.pathComponents
        var path = ""
        return components.enumerated().map { index, component in
            if index == 0 { path = "/" } else { path = URL(fileURLWithPath: path).appending(path: component).path }
            return Breadcrumb(title: index == 0 ? "Macintosh HD" : component, url: URL(fileURLWithPath: path))
        }
    }

    private func navigateToTypedLocation() {
        let path = NSString(string: locationText).expandingTildeInPath
        model.navigate(to: URL(fileURLWithPath: path))
        isEditingLocation = false
    }

    private struct Breadcrumb {
        let title: String
        let url: URL
    }

    @ViewBuilder private var content: some View {
        VStack(spacing: 0) {
            HStack {
                Text(model.currentURL.lastPathComponent.isEmpty ? "Macintosh HD" : model.currentURL.lastPathComponent)
                    .font(.headline)
                Spacer()
                TextField("Search this folder", text: $model.searchText)
                    .textFieldStyle(.roundedBorder).frame(maxWidth: 230)
                    .focused($searchFieldFocused)
                    .onChange(of: model.searchText) { _, query in model.updateSearch(query) }
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            Divider()
            if let error = model.errorMessage {
                ContentUnavailableView("Can’t Open Folder", systemImage: "folder.badge.questionmark", description: Text(error))
            } else if model.isLoading || model.isSearching {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if model.visibleEntries.isEmpty {
                if model.searchText.isEmpty {
                    ContentUnavailableView("This Folder Is Empty", systemImage: "folder", description: Text("Items in this location will appear here."))
                } else {
                    ContentUnavailableView.search(text: model.searchText)
                }
            } else {
                switch model.viewMode {
                case .list: listView
                case .icons: iconView(columns: [GridItem(.adaptive(minimum: 92), spacing: 12)])
                case .compact: compactView
                }
            }
        }
        .background(Color.white)
        .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls) }
        .contextMenu { backgroundContextMenu }
    }

    private var listView: some View {
        GeometryReader { geometry in
            let sizeWidth: CGFloat = 110
            let typeWidth: CGFloat = 150
            let modifiedWidth: CGFloat = 190
            let nameWidth = max(220, geometry.size.width - sizeWidth - typeWidth - modifiedWidth - 24)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    Text("Name").frame(width: nameWidth, alignment: .leading)
                    Text("Size").frame(width: sizeWidth, alignment: .leading)
                    Text("Type").frame(width: typeWidth, alignment: .leading)
                    Text("Date Modified").frame(width: modifiedWidth, alignment: .leading)
                }
                .font(.callout)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
                .frame(height: 34)
                .background(Color(nsColor: .windowBackgroundColor))
                Divider()

                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(treeRows) { row in
                            detailsRow(row, nameWidth: nameWidth, sizeWidth: sizeWidth,
                                       typeWidth: typeWidth, modifiedWidth: modifiedWidth)
                        }
                    }
                }
            }
        }
    }

    private var treeRows: [FileTreeRow] {
        var result: [FileTreeRow] = []
        func append(_ entries: [FileEntry], depth: Int) {
            for entry in entries {
                result.append(FileTreeRow(entry: entry, depth: depth))
                if expandedFolderPaths.contains(entry.path), let children = folderChildren[entry.path] {
                    append(sortedTreeEntries(children), depth: depth + 1)
                }
            }
        }
        append(model.visibleEntries, depth: 0)
        return result
    }

    private func sortedTreeEntries(_ entries: [FileEntry]) -> [FileEntry] {
        entries.sorted { lhs, rhs in
            if lhs.isDirectory != rhs.isDirectory { return lhs.isDirectory }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private func detailsRow(_ row: FileTreeRow, nameWidth: CGFloat, sizeWidth: CGFloat,
                            typeWidth: CGFloat, modifiedWidth: CGFloat) -> some View {
        let entry = row.entry
        return HStack(spacing: 0) {
            HStack(spacing: 6) {
                if entry.isDirectory {
                    Button { toggleFolder(entry) } label: {
                        Group {
                            if foldersLoading.contains(entry.path) {
                                ProgressView().controlSize(.mini)
                            } else {
                                Image(systemName: expandedFolderPaths.contains(entry.path) ? "chevron.down" : "chevron.right")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                        }
                        .frame(width: 16, height: 22)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help(expandedFolderPaths.contains(entry.path) ? "Collapse Folder" : "Expand Folder")
                } else {
                    Color.clear.frame(width: 16, height: 22)
                }
                FileIcon(path: entry.path, size: 18, isFolder: entry.isDirectory)
                    .onTapGesture(count: 2) { model.open(entry) }
                if model.renamingPath == entry.path {
                    InlineRenameField(model: model)
                } else {
                    Text(entry.name)
                        .lineLimit(1)
                        .onTapGesture(count: 2) { model.open(entry) }
                }
                Spacer(minLength: 0)
            }
            .padding(.leading, CGFloat(row.depth) * 20)
            .frame(width: nameWidth, alignment: .leading)

            Text(detailsSize(entry)).foregroundStyle(.secondary)
                .frame(width: sizeWidth, alignment: .leading)
            Text(detailsType(entry)).foregroundStyle(.secondary)
                .frame(width: typeWidth, alignment: .leading)
            Text(Date(timeIntervalSince1970: TimeInterval(entry.modified)),
                 format: .dateTime.month(.abbreviated).day().hour().minute())
                .foregroundStyle(.secondary)
                .frame(width: modifiedWidth, alignment: .leading)
        }
        .font(.callout)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(model.selectedEntryIDs.contains(entry.id) ? Color.accentColor.opacity(0.18) : .clear)
        .contentShape(Rectangle())
        .onTapGesture { model.select(entry, extend: NSEvent.modifierFlags.contains(.command)) }
        .draggable(URL(fileURLWithPath: entry.path))
        .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls, on: entry) }
        .contextMenu { entryContextMenu(entry) }
    }

    private func detailsSize(_ entry: FileEntry) -> String {
        if entry.isDirectory {
            if let children = folderChildren[entry.path] {
                return "\(children.count) item\(children.count == 1 ? "" : "s")"
            }
            return "—"
        }
        return ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)
    }

    private func detailsType(_ entry: FileEntry) -> String {
        if entry.isDirectory { return "Folder" }
        guard !URL(fileURLWithPath: entry.name).pathExtension.isEmpty else { return "Document" }
        return UTType(filenameExtension: URL(fileURLWithPath: entry.name).pathExtension)?.localizedDescription ?? "Document"
    }

    private func toggleFolder(_ entry: FileEntry) {
        if expandedFolderPaths.contains(entry.path) {
            expandedFolderPaths.remove(entry.path)
            return
        }
        expandedFolderPaths.insert(entry.path)
        guard folderChildren[entry.path] == nil else { return }
        foldersLoading.insert(entry.path)
        Task {
            do {
                folderChildren[entry.path] = try await model.loadDirectoryEntries(at: URL(fileURLWithPath: entry.path))
            } catch {
                expandedFolderPaths.remove(entry.path)
                model.operationError = error.localizedDescription
            }
            foldersLoading.remove(entry.path)
        }
    }

    private func iconView(columns: [GridItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.visibleEntries) { entry in
                    VStack(spacing: 7) {
                        FileIcon(path: entry.path, size: model.viewMode == .icons ? 48 * model.iconScale : 24, isFolder: entry.isDirectory)
                            .onTapGesture(count: 2) { model.open(entry) }
                        if model.renamingPath == entry.path {
                            InlineRenameField(model: model)
                        } else {
                            Text(entry.name).font(.system(size: 12 * model.iconScale)).lineLimit(model.viewMode == .icons ? 2 : 1)
                                .multilineTextAlignment(.center)
                                .onTapGesture(count: 2) { model.open(entry) }
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: model.viewMode == .icons ? 90 * model.iconScale : 40)
                    .padding(6)
                    .background(model.selectedEntryIDs.contains(entry.id) ? Color.accentColor.opacity(0.13) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .onTapGesture { model.select(entry, extend: NSEvent.modifierFlags.contains(.command)) }
                    .onTapGesture(count: 2) { model.open(entry) }
                    .draggable(URL(fileURLWithPath: entry.path))
                    .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls, on: entry) }
                    .contextMenu { entryContextMenu(entry) }
                }
            }
            .padding(14)
        }
    }

    private var compactView: some View {
        GeometryReader { geometry in
            let rowHeight: CGFloat = 29
            let rowsPerColumn = max(1, Int(geometry.size.height / rowHeight))
            let entries = model.visibleEntries
            let columnCount = max(1, (entries.count + rowsPerColumn - 1) / rowsPerColumn)
            let columnWidth = max(180, min(260, geometry.size.width / CGFloat(columnCount)))

            ScrollView(.horizontal) {
                HStack(alignment: .top, spacing: 14) {
                    ForEach(0..<columnCount, id: \.self) { column in
                        let start = column * rowsPerColumn
                        let end = min(start + rowsPerColumn, entries.count)
                        VStack(alignment: .leading, spacing: 1) {
                            ForEach(entries[start..<end]) { entry in
                                compactRow(entry, width: columnWidth)
                            }
                        }
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
            }
            .background(Color.white)
            .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls) }
        }
    }

    private func compactRow(_ entry: FileEntry, width: CGFloat) -> some View {
        HStack(spacing: 6) {
            FileIcon(path: entry.path, size: 20 * model.iconScale, isFolder: entry.isDirectory)
            if model.renamingPath == entry.path {
                InlineRenameField(model: model)
            } else {
                Text(entry.name)
                    .font(.system(size: 13 * model.iconScale))
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 4)
        .frame(width: width, height: max(27, 27 * model.iconScale), alignment: .leading)
        .background(model.selectedEntryIDs.contains(entry.id) ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { model.select(entry, extend: NSEvent.modifierFlags.contains(.command)) }
        .onTapGesture(count: 2) { model.open(entry) }
        .draggable(URL(fileURLWithPath: entry.path))
        .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls, on: entry) }
        .contextMenu { entryContextMenu(entry) }
    }

    @ViewBuilder private var backgroundContextMenu: some View {
        Button("Create Folder…") { model.requestNewFolder() }
        Menu("Create Document") {
            Button("Empty File") { model.createNewDocument(asTextFile: false) }
            Button("Text File") { model.createNewDocument(asTextFile: true) }
        }
        Divider()
        Button("Open in Terminal") { model.openInTerminal() }
        Button("Open as Administrator") { }
            .disabled(true)
            .help("macOS does not support Caja’s administrator window mode.")
        Divider()
        Menu("Arrange Items") {
            ForEach(SortMode.allCases) { mode in
                Button {
                    model.sortMode = mode
                    if mode == .name { model.sortAscending = true }
                } label: {
                    if model.sortMode == mode { Label(mode.rawValue, systemImage: "checkmark") }
                    else { Text(mode.rawValue) }
                }
            }
            Divider()
            Toggle("Sort Ascending", isOn: $model.sortAscending)
        }
        Button("Organize by Name") { model.sortMode = .name; model.sortAscending = true }
        Divider()
        Button("Paste") { model.pasteClipboard() }
            .disabled(!NSPasteboard.general.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]))
        Divider()
        Button("Zoom In") { model.zoomIn() }.keyboardShortcut("+", modifiers: .command)
        Button("Zoom Out") { model.zoomOut() }.keyboardShortcut("-", modifiers: .command)
        Button("Normal Size") { model.resetZoom() }.keyboardShortcut("0", modifiers: .command)
        Divider()
        Button("Properties…") { propertiesPath = model.currentURL.path }
    }

    @ViewBuilder private func entryContextMenu(_ entry: FileEntry) -> some View {
        Button("Open") { model.open(entry) }
        if !entry.isDirectory {
            Menu("Open With") {
                Button(model.defaultApplicationName(for: entry)) { model.open(entry) }
                Button("Other Application…") { model.openWithOtherApplication(entry) }
            }
        }
        Divider()
        Button("Cut") { model.selectedEntry = entry; model.copySelectedToClipboard(cut: true) }
        Button("Copy") { model.selectedEntry = entry; model.copySelectedToClipboard() }
        Button("Make Link") { model.selectedEntry = entry; model.makeLinkSelected() }
        Button("Rename…") { model.selectedEntry = entry; model.requestRename() }
        Button("Duplicate") { model.selectedEntry = entry; model.duplicateSelected() }
        Menu("Copy To") {
            Button("Choose Destination…") { model.selectedEntry = entry; model.chooseTransferDestination(move: false) }
        }
        Menu("Move To") {
            Button("Choose Destination…") { model.selectedEntry = entry; model.chooseTransferDestination(move: true) }
        }
        Divider()
        Button("Move to Trash", role: .destructive) { model.selectedEntry = entry; model.moveSelectedToTrash() }
        Button("Open as Administrator") { }
            .disabled(true)
            .help("macOS does not support Caja’s administrator window mode.")
        ShareLink(item: URL(fileURLWithPath: entry.path)) {
            Label("Send To…", systemImage: "square.and.arrow.up")
        }
        Divider()
        Button("Properties…") { propertiesPath = entry.path }
        Button("Reveal in Finder") { NSWorkspace.shared.selectFile(entry.path, inFileViewerRootedAtPath: "") }
    }

}

private struct FileIcon: View {
    let path: String
    let size: CGFloat
    var isFolder = false
    @State private var isHovered = false

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
            .brightness(isFolder && isHovered ? 0.12 : 0)
            .scaleEffect(isFolder && isHovered ? 1.045 : 1)
            .animation(.easeOut(duration: 0.14), value: isHovered)
            .onHover { isHovered = $0 }
            .accessibilityHidden(true)
    }
}

private struct InlineRenameField: View {
    @Bindable var model: BrowserModel
    @FocusState private var isFocused: Bool

    var body: some View {
        TextField("Name", text: $model.renameName)
            .textFieldStyle(.plain)
            .accessibilityLabel("Rename file")
            .focused($isFocused)
            .onAppear {
                isFocused = true
            }
            .onSubmit { model.renameSelected(to: model.renameName) }
            .onKeyPress(.escape) {
                model.cancelRename()
                return .handled
            }
    }
}

private struct FilePropertiesView: View {
    let path: String
    @Environment(\.dismiss) private var dismiss
    @State private var selectedTab = 0
    @State private var contentsSummary: String?
    @State private var permissionMode = 0
    @State private var permissionError: String?

    private var url: URL { URL(fileURLWithPath: path) }
    private var attributes: [FileAttributeKey: Any] { (try? FileManager.default.attributesOfItem(atPath: path)) ?? [:] }
    private var isDirectory: Bool { (attributes[.type] as? FileAttributeType) == .typeDirectory }
    private var kind: String {
        if isDirectory { return "Folder" }
        let ext = url.pathExtension
        guard !ext.isEmpty else { return "Document" }
        return UTType(filenameExtension: ext)?.localizedDescription ?? "\(ext.uppercased()) Document"
    }
    private var size: String {
        guard let bytes = attributes[.size] as? NSNumber else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file)
    }
    private var volumeInfo: [FileAttributeKey: Any] {
        (try? FileManager.default.attributesOfFileSystem(forPath: path)) ?? [:]
    }
    private var volumeName: String {
        let values = try? url.resourceValues(forKeys: [.volumeNameKey])
        return values?.volumeName ?? url.deletingLastPathComponent().path
    }
    private var freeSpace: String {
        guard let bytes = volumeInfo[.systemFreeSize] as? NSNumber else { return "—" }
        return ByteCountFormatter.string(fromByteCount: bytes.int64Value, countStyle: .file)
    }
    private func date(_ key: FileAttributeKey) -> String {
        guard let value = attributes[key] as? Date else { return "—" }
        return value.formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(spacing: 0) {
            Picker("Properties", selection: $selectedTab) {
                Text("Basic").tag(0)
                Text("Permissions").tag(1)
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top], 18)

            Group {
                if selectedTab == 0 { basicTab } else { permissionsTab }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(20)

            Divider()
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
            .padding(16)
        }
        .frame(width: 520, height: isDirectory ? 430 : 360)
        .task(id: path) {
            permissionMode = (attributes[.posixPermissions] as? NSNumber)?.intValue ?? 0
            guard isDirectory else { return }
            let folder = url
            contentsSummary = await Task.detached(priority: .utility) {
                Self.summarizeContents(of: folder)
            }.value
        }
    }

    private var basicTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 14) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 56, height: 56)
                VStack(alignment: .leading, spacing: 4) {
                    Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(kind).foregroundStyle(.secondary)
                }
            }
            Divider()
            if isDirectory {
                propertyRow("Contents", contentsSummary ?? "Calculating…")
                propertyRow("Location", url.deletingLastPathComponent().path)
                propertyRow("Volume", volumeName)
                propertyRow("Free space", freeSpace)
            } else {
                propertyRow("Location", url.deletingLastPathComponent().path)
                propertyRow("Size", size)
            }
            propertyRow("Created", date(.creationDate))
            propertyRow("Modified", date(.modificationDate))
            Spacer(minLength: 0)
        }
    }

    private var permissionsTab: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Permissions for this folder").font(.headline)
            Text("Changes apply to this folder only.")
                .font(.callout).foregroundStyle(.secondary)
            Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 12) {
                GridRow {
                    Text("")
                    Text("Read").foregroundStyle(.secondary)
                    Text("Write").foregroundStyle(.secondary)
                    Text("Execute").foregroundStyle(.secondary)
                }
                permissionRow("Owner", read: 0o400, write: 0o200, execute: 0o100)
                permissionRow("Group", read: 0o040, write: 0o020, execute: 0o010)
                permissionRow("Everyone", read: 0o004, write: 0o002, execute: 0o001)
            }
            Divider()
            propertyRow("Owner", attributes[.ownerAccountName] as? String ?? "—")
            propertyRow("Group", attributes[.groupOwnerAccountName] as? String ?? "—")
            propertyRow("Modified", date(.modificationDate))
            if let permissionError {
                Text(permissionError).font(.callout).foregroundStyle(.red)
            }
            Spacer(minLength: 0)
        }
    }

    private func permissionRow(_ title: String, read: Int, write: Int, execute: Int) -> some View {
        GridRow {
            Text(title).frame(minWidth: 74, alignment: .leading)
            permissionToggle("Read", bit: read)
            permissionToggle("Write", bit: write)
            permissionToggle("Execute", bit: execute)
        }
    }

    private func permissionToggle(_ label: String, bit: Int) -> some View {
        Toggle(label, isOn: Binding(
            get: { permissionMode & bit != 0 },
            set: { enabled in
                let updated = enabled ? permissionMode | bit : permissionMode & ~bit
                do {
                    try FileManager.default.setAttributes([.posixPermissions: NSNumber(value: updated)], ofItemAtPath: path)
                    permissionMode = updated
                    permissionError = nil
                } catch {
                    permissionError = error.localizedDescription
                }
            }
        ))
        .labelsHidden()
        .accessibilityLabel(label)
    }

    nonisolated private static func summarizeContents(of url: URL) -> String {
        guard let enumerator = FileManager.default.enumerator(at: url, includingPropertiesForKeys: [.isDirectoryKey, .fileSizeKey], options: [.skipsHiddenFiles]) else {
            return "Unable to read contents"
        }
        var count = 0
        var bytes: Int64 = 0
        for case let item as URL in enumerator {
            count += 1
            if let values = try? item.resourceValues(forKeys: [.isDirectoryKey, .fileSizeKey]), values.isDirectory != true {
                bytes += Int64(values.fileSize ?? 0)
            }
        }
        let countText = "\(count) item\(count == 1 ? "" : "s")"
        return count == 0 ? "nothing" : "\(countText), \(ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file))"
    }

    private func propertyRow(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(label).foregroundStyle(.secondary).frame(width: 84, alignment: .trailing)
            Text(value).textSelection(.enabled).lineLimit(2)
            Spacer(minLength: 0)
        }
        .font(.callout)
    }
}

private struct PlacesSidebar: View {
    @Bindable var model: BrowserModel
    private let home = FileManager.default.homeDirectoryForCurrentUser

    var body: some View {
        List {
            Section("Places") {
                place("Home", icon: "house", url: home)
                place("Desktop", icon: "menubar.dock.rectangle", url: home.appending(path: "Desktop"))
                place("Documents", icon: "doc", url: home.appending(path: "Documents"))
                place("Downloads", icon: "arrow.down.circle", url: home.appending(path: "Downloads"))
                place("Applications", icon: "square.grid.2x2", url: URL(fileURLWithPath: "/Applications"))
            }
            if !model.bookmarks.isEmpty {
                Section("Bookmarks") {
                    ForEach(model.bookmarks) { bookmark in
                        Button { model.navigate(to: bookmark.url) } label: {
                            Label(bookmark.name, systemImage: "bookmark")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 8).padding(.vertical, 6)
                                .background(isCurrent(bookmark.url) ? Color.accentColor.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 7))
                                .contentShape(Rectangle())
                                .fontWeight(isCurrent(bookmark.url) ? .bold : .regular)
                        }
                        .buttonStyle(.plain)
                            .contextMenu {
                                Button("Remove Bookmark") { model.removeBookmark(bookmark) }
                            }
                    }
                }
            }
            Section("Devices") {
                place("Macintosh HD", icon: "internaldrive", url: URL(fileURLWithPath: "/"))
                ForEach(volumes, id: \.path) { url in place(url.lastPathComponent, icon: "externaldrive", url: url) }
            }
            Section("Network") {
                Label("Network", systemImage: "network")
                    .foregroundStyle(.secondary)
                    .help("Network locations will be added with remote filesystem support.")
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Color(nsColor: .underPageBackgroundColor))
    }

    private var volumes: [URL] {
        (try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/Volumes"),
             includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
    }

    private func place(_ title: String, icon: String, url: URL) -> some View {
        Button { model.navigate(to: url) } label: {
            Label(title, systemImage: icon)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 8).padding(.vertical, 6)
                .background(isCurrent(url) ? Color.accentColor.opacity(0.16) : .clear,
                            in: RoundedRectangle(cornerRadius: 7))
                .contentShape(Rectangle())
                .fontWeight(isCurrent(url) ? .bold : .regular)
        }
        .buttonStyle(.plain)
        .foregroundStyle(Color.primary)
    }

    private func isCurrent(_ url: URL) -> Bool {
        model.currentURL.standardizedFileURL.path == url.standardizedFileURL.path
    }
}
