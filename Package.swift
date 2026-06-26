// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "wetrans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "wetrans", targets: ["wetransApp"]),
        .executable(name: "wetrans-e2e", targets: ["wetransE2E"])
    ],
    targets: [
        .target(
            name: "wetrans",
            path: "wetrans"
        ),
        .executableTarget(
            name: "wetransApp",
            dependencies: ["wetrans"],
            path: "wetransApp"
        ),
        .executableTarget(
            name: "wetransE2E",
            path: "wetransE2E"
        ),
        .testTarget(
            name: "wetransTests",
            dependencies: ["wetrans"],
            path: "wetransTests"
        )
    ]
)
