// swift-tools-version: 5.10
//
// Rotoskop core package.
//
// This package contains ONLY platform-agnostic library code so that it can be
// built and tested on Linux (`swift build` / `swift test`) as well as on macOS
// via Xcode. Nothing here may import UIKit or SwiftUI. All UI lives in the iOS
// app under `App/`, which consumes this package as a local path dependency.

import PackageDescription

let package = Package(
    name: "Rotoskop",
    products: [
        // The 6502 + simplified Apple II/III emulation core.
        .library(name: "RotoskopEmulator", targets: ["RotoskopEmulator"]),
        // File model + abstract file system used by the file browser.
        .library(name: "RotoskopWorkspace", targets: ["RotoskopWorkspace"]),
        // Git provider protocols + value types used by the repo list / sync.
        .library(name: "RotoskopGit", targets: ["RotoskopGit"]),
        // Text document model backing the code editor.
        .library(name: "RotoskopEditorCore", targets: ["RotoskopEditorCore"]),
    ],
    targets: [
        // MARK: Emulator
        .target(name: "RotoskopEmulator"),
        .testTarget(
            name: "RotoskopEmulatorTests",
            dependencies: ["RotoskopEmulator"]
        ),

        // MARK: Workspace / files
        .target(name: "RotoskopWorkspace"),
        .testTarget(
            name: "RotoskopWorkspaceTests",
            dependencies: ["RotoskopWorkspace"]
        ),

        // MARK: Git
        .target(name: "RotoskopGit"),
        .testTarget(
            name: "RotoskopGitTests",
            dependencies: ["RotoskopGit"]
        ),

        // MARK: Editor core
        .target(name: "RotoskopEditorCore"),
        .testTarget(
            name: "RotoskopEditorCoreTests",
            dependencies: ["RotoskopEditorCore"]
        ),
    ]
)
