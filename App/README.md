# Rotoskop iOS app

This is the thin SwiftUI layer that consumes the core `Rotoskop` Swift package
(one directory up). It is **not** built on Linux and is not part of
`Package.swift` — keeping the app out of the package is what lets the core
libraries build and test in a Linux sandbox / CI.

## Generating the Xcode project

The `.xcodeproj` is generated (and git-ignored) via [XcodeGen] from
`project.yml`:

```bash
brew install xcodegen        # one-time
cd App
xcodegen generate            # creates Rotoskop.xcodeproj
open Rotoskop.xcodeproj
```

The project declares a local Swift Package dependency on `..`, so the app links
`RotoskopEmulator`, `RotoskopWorkspace`, `RotoskopGit`, and
`RotoskopEditorCore` directly from source.

## What lives here vs. in the package

The app supplies the platform-specific pieces the core defines as protocols:

- SwiftUI views (repo list, file browser, editor, debugger).
- A `UITextView`-based editor with iOS typing "conveniences" disabled.
- A Foundation `FileManager`-backed `FileSystem`.
- A concrete `GitService` (libgit2/SwiftGit2 — TBD) + Keychain credentials.

Right now this contains only a minimal app shell (`RotoskopApp` +
`ContentView`) that boots the emulator and renders its text screen, proving the
package↔app wiring end to end. Real UI arrives as each component is built.

[XcodeGen]: https://github.com/yonaskolb/XcodeGen
