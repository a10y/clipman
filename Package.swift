// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Clipman",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Clipman",
            path: "Sources/Clipman",
            linkerSettings: [.linkedFramework("Carbon")]
        ),
        .testTarget(
            name: "ClipmanTests",
            dependencies: ["Clipman"],
            path: "Tests/ClipmanTests"
        ),
    ]
)
