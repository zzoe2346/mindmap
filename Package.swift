// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mindmap",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Mindmap", targets: ["MindmapApp"])],
    targets: [
        .target(name: "MindmapCore"),
        .executableTarget(name: "MindmapApp", dependencies: ["MindmapCore"]),
        .testTarget(name: "MindmapCoreTests", dependencies: ["MindmapCore"]),
        .testTarget(name: "MindmapAppTests", dependencies: ["MindmapApp", "MindmapCore"]),
    ],
    swiftLanguageModes: [.v6]
)
