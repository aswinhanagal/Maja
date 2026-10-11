# Maja feature inventory

This is a living parity checklist for a Caja-inspired macOS file manager. Caja's MATE-specific desktop shell integration is out of scope where macOS provides no equivalent; file-manager behavior remains in scope where it can be mapped to native macOS services.

## Foundation

- [x] Native macOS app shell and Caja-like window composition
- [x] Open Folder dialog using the native macOS panel
- [x] Places, bookmarks, and mounted-volume sidebar
- [x] Editable location entry, breadcrumb path bar, back/forward/up, refresh
- [x] List, icon, and compact view modes
- [x] Hidden files, basic name filtering, file opening
- [x] Sort by name, kind, size, or modified time; remember display preferences
- [x] Multiple windows, in-window tabs, and close/new-tab shortcuts

## Navigation and presentation

- [ ] Browser and spatial window modes
- [ ] Sidebar modes: Places, tree, history, notes, information
- [x] Bookmarks and bookmark editor (add/remove; names currently use the folder name)
- [x] Breadcrumb path bar and editable location mode
- [x] Sorting by name, kind, size, and modified time
- [ ] Columns, zoom, icon layout and per-folder view preferences
- [x] Single-item selection and context menus
- [ ] Multi-selection, keyboard navigation, and drag and drop
- [ ] Thumbnails and previews, including list-view thumbnails
- [ ] Emblems, custom icons, and per-folder background/emblem customization

## File operations

- [x] Create folders; rename and duplicate
- [x] Copy, move, and trash through native macOS Trash
- [ ] Restore, permanent delete, and link creation
- [ ] Conflict handling, progress, cancellation, undo, and redo
- [ ] Properties, permissions, ownership display, and disk usage
- [ ] Open with, default application selection, and executable handling
- [ ] Volume mounting/ejecting and removable-device handling

## Search, metadata, and preferences

- [x] Recursive search by name within the current location (capped at 5,000 results)
- [ ] Content/metadata search and saved searches
- [ ] Metadata and media tags; file type and MIME information
- [ ] Preferences for behavior, display, columns, previews, and performance
- [ ] Session restore, keyboard shortcuts, localization, and accessibility

## Remote files and extensibility

- [ ] Network locations and supported remote protocols
- [ ] Archives, image mounting, and other service integrations
- [ ] User-defined scripts and context-menu actions
- [ ] Extension API and migration path for suitable Caja action concepts

## Host-specific mapping

- MATE desktop icons become Finder-compatible opening/reveal behavior; Maja will not replace Finder's desktop.
- MATE panel, session, GSettings, and D-Bus integration map to macOS menu, preferences, login/session, and notification facilities where appropriate.
- GVfs backends map to macOS file URLs, mounted volumes, and explicitly supported remote providers. Protocol coverage will be documented rather than implied.
- Filesystem enumeration and operations run in-process through the Rust static library so privacy access applies to Maja itself rather than a spawned helper.
