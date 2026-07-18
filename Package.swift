// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Rotoskop",
    platforms: [
        .macOS(.v14),
        .iOS(.v17),
    ],
    products: [
        .library(name: "RotoskopCore", targets: ["RotoskopCore"]),
        .executable(name: "rotoskop", targets: ["rotoskop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .target(
            name: "RotoskopCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/RotoskopCore"
        ),
        .executableTarget(
            name: "rotoskop",
            dependencies: ["RotoskopCore"],
            path: "Sources/rotoskop"
        ),
        .testTarget(
            name: "RotoskopCoreTests",
            dependencies: ["RotoskopCore"],
            path: "Tests/RotoskopCoreTests"
        ),
    ]
)
