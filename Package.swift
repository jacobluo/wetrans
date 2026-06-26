// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "wetrans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "wetrans", targets: ["wetransApp"])
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
        .testTarget(
            name: "wetransTests",
            dependencies: ["wetrans"],
            path: "wetransTests"
        )
    ]
)

