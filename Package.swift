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
        .library(name: "RotoskopGit", targets: ["RotoskopGit"]),
        .library(name: "RotoskopUI", targets: ["RotoskopUI"]),
        .executable(name: "rotoskop", targets: ["rotoskop"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        // Same libgit2 SPM fork SwiftGitX uses; we wrap it directly because we need
        // PAT credentials, pull, and clean-merge (SwiftGitX still TODOs those).
        .package(url: "https://github.com/ibrahimcetin/libgit2.git", exact: "1.9.2"),
    ],
    targets: [
        .target(
            name: "RotoskopCore",
            dependencies: [
                .product(name: "Yams", package: "Yams"),
            ],
            path: "Sources/RotoskopCore"
        ),
        .target(
            name: "RotoskopGit",
            dependencies: [
                .product(name: "libgit2", package: "libgit2"),
            ],
            path: "Sources/RotoskopGit"
        ),
        .target(
            name: "RotoskopUI",
            dependencies: ["RotoskopGit", "RotoskopCore"],
            path: "Sources/RotoskopUI"
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
        .testTarget(
            name: "RotoskopGitTests",
            dependencies: ["RotoskopGit"],
            path: "Tests/RotoskopGitTests"
        ),
        .testTarget(
            name: "RotoskopUITests",
            dependencies: ["RotoskopUI"],
            path: "Tests/RotoskopUITests"
        ),
    ]
)
