// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacTimer",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacTimer", targets: ["MacTimer"]),
        .executable(name: "MacTimerHost", targets: ["MacTimerHost"]),
        .executable(name: "MacTimerPreview", targets: ["MacTimerPreview"]),
    ],
    targets: [
        .target(
            name: "MacTimerCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "MacTimerUI", dependencies: ["MacTimerCore"]),
        .executableTarget(
            name: "MacTimer",
            dependencies: ["MacTimerUI", "MacTimerCore"]
        ),
        .executableTarget(
            name: "MacTimerHost",
            dependencies: ["MacTimerCore"]
        ),
        .executableTarget(
            name: "MacTimerPreview",
            dependencies: ["MacTimerUI", "MacTimerCore"]
        ),
        .testTarget(
            name: "MacTimerCoreTests",
            dependencies: ["MacTimerCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "MacTimerUITests",
            dependencies: ["MacTimerUI", "MacTimerCore"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
    ]
)
