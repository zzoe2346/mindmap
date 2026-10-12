// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Mindmap",
    platforms: [.macOS("26.0")],
    products: [.library(name: "MindmapCore", targets: ["MindmapCore"])],
    targets: [
        .target(name: "MindmapCore"),
        .testTarget(name: "MindmapCoreTests", dependencies: ["MindmapCore"]),
    ],
    swiftLanguageModes: [.v6]
)
