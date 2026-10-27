// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "kdrive-open-local",
    platforms: [.macOS(.v12)],
    targets: [
        .systemLibrary(name: "CSQLite", path: "Sources/CSQLite"),
        .target(name: "KDriveResolver", dependencies: ["CSQLite"]),
        .executableTarget(name: "kdrive-open-local", dependencies: ["KDriveResolver"]),
        .testTarget(name: "KDriveResolverTests", dependencies: ["KDriveResolver", "CSQLite"]),
    ]
)
