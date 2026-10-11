# Maja

Maja is a native macOS reimplementation of the Caja file manager. It aims to preserve Caja's recognizable browser layout and bring across the features that can be meaningfully supported on macOS.

## License

Maja is free software licensed under the GNU General Public License, version 2 or (at your option) any later version. See [LICENSE](LICENSE) for the complete license text.

## Current foundation

- Rust workspace for filesystem enumeration and file-operation logic, linked into the app process through a C ABI.
- SwiftUI/AppKit macOS application shell.
- Caja-style Places and Devices sidebar, location entry, navigation controls, and icon/list/compact views.
- Local directory navigation, a native Open Folder panel, hidden-file toggle, recursive name search, double-click open, and status line.
- In-window tabs, persistent bookmarks, file operations, and sort preferences.
- An in-process Rust boundary keeps filesystem work in Rust while macOS privacy permissions stay attached to Maja.

## Build

Requirements: macOS 14 or later, Rust, and Xcode Command Line Tools.

```sh
./scripts/build-app.sh
open outputs/Maja.app
```

During development, build the Rust backend with `cargo build --release -p maja-core` before launching the SwiftPM app so its static Rust library is available to the linker.

## Feature direction

The implementation will be tracked against Caja's source and organized into navigation and views, file operations, search and metadata, preferences, remote locations, and extensions/actions. MATE desktop ownership features (desktop icons, panel integration, and MATE settings) have no direct macOS host equivalent and will be mapped to native Mac behavior where possible.
