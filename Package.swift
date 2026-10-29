// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacDirStat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "MacDirStat",
            targets: ["MacDirStat"]
        )
    ],
    targets: [
        .executableTarget(
            name: "MacDirStat",
            path: "Sources/MacDirStat"
        ),
        .testTarget(
            name: "MacDirStatTests",
            dependencies: ["MacDirStat"],
            path: "Tests/MacDirStatTests"
        )
    ]
)
