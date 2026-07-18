# Rotoskop

Bespoke mini IDE for 6502 assembly targeting a simplified Apple II/III-style emulator. Offline-first, occasional GitHub sync. Primary project: Runix on its `rotoskop` branch (`for_ref/runix` locally).

**Audience:** one. **Design:** see [`DESIGN.md`](DESIGN.md) — implement to that document.

## Status

Steps **0–5** done: scaffold, emulator, assembler, YAML build/pack, Runix `rotoskop` branch, **app shell + Git**. **Next:** file browser + editor (§2–3).

## Layout

| Path | Role |
|------|------|
| `DESIGN.md` | Product/architecture design (source of truth) |
| `Package.swift` | SwiftPM: `RotoskopCore`, `RotoskopGit`, `RotoskopUI`, `rotoskop` CLI |
| `Sources/RotoskopCore` | Emulator, assembler, build/pack, run session |
| `Sources/RotoskopGit` | libgit2 Git ops, Keychain PAT, project store |
| `Sources/RotoskopUI` | SwiftUI shell (repo list, tabs, Git sheet) |
| `Sources/rotoskop` | Mac CLI (`build`, `assemble`, `run`) |
| `Tests/` | Unit/integration tests (no UI device required) |
| `Apps/Rotoskop` | iOS app target (Xcode project) |
| `Scripts/run-on-device.sh` | Build + install + launch on a connected iPhone |
| `for_ref/runix` | Editable Runix checkout on `rotoskop` (gitignored). **Only** edit Runix here—not a separate `runix` tree elsewhere. |

## Build & test (Mac)

Requires Xcode (Swift 6+).

```bash
swift build
swift test
swift run rotoskop --help
```

**Stay green** (after meaningful changes): `swift test`; `swift run rotoskop build for_ref/runix`; `swift run rotoskop run for_ref/runix --profile halt`. When touching the iOS app: `Scripts/run-on-device.sh`.

### Against Runix

```bash
RUNIX=for_ref/runix
swift run rotoskop build "$RUNIX"
swift run rotoskop run "$RUNIX" --profile halt -v --screen
```

### iOS app

```bash
open Apps/Rotoskop/Rotoskop.xcodeproj
# or on a connected phone:
Scripts/run-on-device.sh
# or simulator:
xcodebuild -project Apps/Rotoskop/Rotoskop.xcodeproj -scheme Rotoskop \
  -destination 'platform=iOS Simulator,name=iPhone 17' build
```

### Assembler / build

```bash
swift run rotoskop assemble path/to/file.s -o out.bin -I include/dir [--list out.lst]
swift run rotoskop build [project-root]
```

Assemble is a ca65 subset → raw binary (no linker). Build reads `rotoskop.yaml` (`generate` / `assemble` / `pack_image`).

## Reference

| Path | Role |
|------|------|
| `DESIGN.md` | Design |
| `for_ref/runix` | Runix daily driver + Make/ca65 golden until cutover |
| `for_ref/runix/pim65` | Python emulator this Swift core ports/improves |

## License / ownership

Personal project.
