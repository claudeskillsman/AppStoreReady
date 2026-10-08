// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AppStoreReady",
    platforms: [
        .macOS(.v13),
    ],
    products: [
        .executable(name: "appstoreready", targets: ["AppStoreReadyCLI"]),
        .library(name: "AppStoreReadyCore", targets: ["AppStoreReadyCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "AppStoreReadyCore"
        ),
        .executableTarget(
            name: "AppStoreReadyCLI",
            dependencies: [
                "AppStoreReadyCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ]
        ),
        .testTarget(
            name: "AppStoreReadyCoreTests",
            dependencies: ["AppStoreReadyCore"]
        ),
    ]
)
