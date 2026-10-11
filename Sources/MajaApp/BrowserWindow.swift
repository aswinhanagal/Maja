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

private struct BrowserPane: View {
    @Bindable var model: BrowserModel
    let newTab: () -> Void
    let closeTab: () -> Bool
    @State private var locationText = ""
    @State private var isEditingLocation = false
    @State private var showSidebar = true
    @State private var propertiesPath: String?
    @FocusState private var locationFieldFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            HSplitView {
                if showSidebar {
                    PlacesSidebar(model: model)
                        .frame(minWidth: 170, idealWidth: 210, maxWidth: 280)
                }
                content
                    .frame(minWidth: 420, maxWidth: .infinity, maxHeight: .infinity)
            }
            Divider()
            HStack(spacing: 6) {
                Text("\(model.visibleEntries.count) items")
                if let selected = model.selectedEntry { Text("• \(selected.name) selected") }
                Spacer()
                Text(model.currentURL.path).lineLimit(1).truncationMode(.middle)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12).padding(.vertical, 6)
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
            hasSelection: model.selectedEntry != nil,
            addBookmark: model.addCurrentBookmark,
            newTab: newTab,
            closeTab: closeTab,
            openFolder: model.openFolderPicker
        ))
    }

    private var toolbar: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Button { model.goBack() } label: { Image(systemName: "chevron.left") }
                    .disabled(!model.canGoBack).help("Back")
                Button { model.goForward() } label: { Image(systemName: "chevron.right") }
                    .disabled(!model.canGoForward).help("Forward")
                Button { model.goUp() } label: { Image(systemName: "arrow.up") }.help("Enclosing Folder")
                Button { model.navigate(to: FileManager.default.homeDirectoryForCurrentUser) } label: { Image(systemName: "house") }.help("Home")
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
        Table(model.visibleEntries, selection: Binding(
            get: { model.selectedEntry?.id },
            set: { id in model.selectedEntry = model.visibleEntries.first { $0.id == id } }
        )) {
            TableColumn("Name") { entry in
                HStack(spacing: 8) {
                    FileIcon(path: entry.path, size: 18)
                    if model.renamingPath == entry.path {
                        InlineRenameField(model: model)
                    } else {
                        Text(entry.name).lineLimit(1)
                    }
                }
                .draggable(URL(fileURLWithPath: entry.path))
                .dropDestination(for: URL.self) { urls, _ in model.acceptDrop(urls, on: entry) }
                .contentShape(Rectangle())
                .onTapGesture(count: 2) { model.open(entry) }
            }
            .width(min: 180, ideal: 300)
            TableColumn("Size") { entry in Text(entry.isDirectory ? "—" : ByteCountFormatter.string(fromByteCount: Int64(entry.size), countStyle: .file)).foregroundStyle(.secondary) }
                .width(min: 70, ideal: 90)
            TableColumn("Modified") { entry in
                Text(Date(timeIntervalSince1970: TimeInterval(entry.modified)), format: .dateTime.month(.abbreviated).day().hour().minute())
                    .foregroundStyle(.secondary)
            }.width(min: 130, ideal: 150)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if let entry = model.visibleEntries.first(where: { ids.contains($0.id) }) {
                entryContextMenu(entry)
            }
        } primaryAction: { ids in
            if let entry = model.visibleEntries.first(where: { ids.contains($0.id) }) { model.open(entry) }
        }
    }

    private func iconView(columns: [GridItem]) -> some View {
        ScrollView {
            LazyVGrid(columns: columns, alignment: .leading, spacing: 12) {
                ForEach(model.visibleEntries) { entry in
                    VStack(spacing: 7) {
                        FileIcon(path: entry.path, size: model.viewMode == .icons ? 48 * model.iconScale : 24)
                        if model.renamingPath == entry.path {
                            InlineRenameField(model: model)
                        } else {
                            Text(entry.name).font(.system(size: 12 * model.iconScale)).lineLimit(model.viewMode == .icons ? 2 : 1)
                                .multilineTextAlignment(.center)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: model.viewMode == .icons ? 90 * model.iconScale : 40)
                    .padding(6)
                    .background(model.selectedEntry == entry ? Color.accentColor.opacity(0.13) : .clear,
                                in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(Rectangle())
                    .onTapGesture { model.selectedEntry = entry }
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
            FileIcon(path: entry.path, size: 20 * model.iconScale)
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
        .background(model.selectedEntry == entry ? Color.accentColor.opacity(0.18) : .clear,
                    in: RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .onTapGesture { model.selectedEntry = entry }
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

    var body: some View {
        Image(nsImage: NSWorkspace.shared.icon(forFile: path))
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
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
    private func date(_ key: FileAttributeKey) -> String {
        guard let value = attributes[key] as? Date else { return "—" }
        return value.formatted(date: .long, time: .shortened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: path))
                    .resizable().aspectRatio(contentMode: .fit).frame(width: 48, height: 48)
                VStack(alignment: .leading, spacing: 3) {
                    Text(url.lastPathComponent).font(.title3.weight(.semibold)).lineLimit(1)
                    Text(kind).foregroundStyle(.secondary)
                }
            }
            Divider()
            propertyRow("Where", url.deletingLastPathComponent().path)
            propertyRow("Size", size)
            propertyRow("Created", date(.creationDate))
            propertyRow("Modified", date(.modificationDate))
            if let permissions = attributes[.posixPermissions] as? NSNumber {
                propertyRow("Permissions", String(format: "%04o", permissions.intValue))
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button("Done") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding(22)
        .frame(width: 440, height: 330)
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
                        Label(bookmark.name, systemImage: "bookmark")
                            .contentShape(Rectangle())
                            .onTapGesture { model.navigate(to: bookmark.url) }
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
        Label(title, systemImage: icon)
            .contentShape(Rectangle())
            .onTapGesture { model.navigate(to: url) }
            .foregroundStyle(model.currentURL == url.standardizedFileURL ? Color.accentColor : Color.primary)
    }
}
