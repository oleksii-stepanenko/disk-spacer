// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DiskSpacer",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "DiskSpacerCore", targets: ["DiskSpacerCore"]),
        .executable(name: "diskspacer", targets: ["diskspacer-cli"]),
        .executable(name: "DiskSpacerApp", targets: ["DiskSpacerApp"]),
    ],
    targets: [
        .target(name: "DiskSpacerCore"),
        .executableTarget(name: "diskspacer-cli", dependencies: ["DiskSpacerCore"]),
        .executableTarget(name: "DiskSpacerApp", dependencies: ["DiskSpacerCore"]),
        .testTarget(name: "DiskSpacerCoreTests", dependencies: ["DiskSpacerCore"]),
    ]
)
