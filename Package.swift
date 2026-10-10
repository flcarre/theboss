// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TheBoss",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "TheBoss", targets: ["TheBoss"]),
    ],
    targets: [
        .target(
            name: "BossCore",
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .executableTarget(
            name: "TheBoss",
            dependencies: ["BossCore"],
            resources: [.copy("Assets")]
        ),
        .testTarget(
            name: "BossCoreTests",
            dependencies: ["BossCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
