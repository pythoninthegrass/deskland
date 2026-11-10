// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Deskland",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "DesklandCore"),
        .executableTarget(
            name: "DesklandMac",
            dependencies: ["DesklandCore"],
            exclude: ["Info.plist"],
            linkerSettings: [
                // Gives a bare `swift run` binary the same LSUIElement and identity as the app bundle.
                .unsafeFlags(["-Xlinker", "-sectcreate", "-Xlinker", "__TEXT", "-Xlinker", "__info_plist",
                              "-Xlinker", "Sources/DesklandMac/Info.plist"]),
            ]),
        .testTarget(name: "DesklandCoreTests", dependencies: ["DesklandCore"]),
    ]
)
