# Rotoskop

A bespoke, offline-first iOS mini-IDE for writing **6502 assembly** targeting a
simplified Apple II/III emulation core. Audience: one. Goal: code entirely
offline on an iPad/iPhone, sync to GitHub occasionally.

## What's here today

The project is organised as a **Swift Package of pure-logic libraries** plus a
thin iOS app that consumes them. Everything that can be is written to build and
test on Linux (`swift build` / `swift test`), so the core logic is developed and
verified without needing Xcode or a device.

```
Rotoskop/
├── Package.swift              SwiftPM manifest (libraries only — no UI)
├── Sources/
│   ├── RotoskopEmulator/      6502 CPU, memory map, text screen, debug (focus)
│   ├── RotoskopWorkspace/     File model + abstract FileSystem (file browser)
│   ├── RotoskopGit/           Git provider protocol + value types (repo sync)
│   └── RotoskopEditorCore/    Text document model (code editor)
├── Tests/                     XCTest suites, all run on Linux
├── App/                       iOS app (SwiftUI) — built with Xcode/XcodeGen
└── ARCHITECTURE.md            Design + component outline (read this next)
```

See [`ARCHITECTURE.md`](ARCHITECTURE.md) for the full picture and roadmap.

## Building & testing (Linux or macOS)

```bash
swift build      # compile all core libraries
swift test       # run the full XCTest suite (29 tests today)
```

The Swift toolchain used in CI/dev sandbox is Swift 6.1 (language mode 5).

## The iOS app

The app under `App/` is not built on Linux. It references this package as a
local path dependency and is generated/opened via Xcode (an XcodeGen
`project.yml` is provided). See `App/README.md`.

## Status

Early scaffolding. The emulator core currently implements a representative slice
of the official NMOS 6502 instruction set (every instruction *family* plus the
addressing/flag/cycle machinery) as the foundation for porting an existing
Python 6502 core into the `InstructionSet` dispatch table.
