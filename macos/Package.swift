// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Deskland",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DesklandCore"),
        .testTarget(name: "DesklandCoreTests", dependencies: ["DesklandCore"]),
    ]
)
