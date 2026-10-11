// swift-tools-version: 6.0
import PackageDescription
import Foundation

let rustLibraryDirectory = URL(fileURLWithPath: #filePath)
    .deletingLastPathComponent()
    .appending(path: "target/release")
    .path

let package = Package(
    name: "Maja",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Maja", targets: ["MajaApp"])],
    targets: [
        .systemLibrary(name: "MajaCoreFFI", path: "Sources/MajaCoreFFI"),
        .executableTarget(
            name: "MajaApp",
            dependencies: ["MajaCoreFFI"],
            path: "Sources/MajaApp",
            resources: [.copy("Resources/MajaIcon.svg")],
            linkerSettings: [.unsafeFlags(["-L\(rustLibraryDirectory)"], .when(platforms: [.macOS])), .linkedLibrary("maja_core")]
        )
    ]
)
