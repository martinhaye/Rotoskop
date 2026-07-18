# Rotoskop

Bespoke mini IDE for 6502 assembly targeting a simplified Apple II/III-style emulator. Offline-first, occasional GitHub sync. Primary project: Runix on its `rotoskop` branch (`for_ref/runix` locally).

**Audience:** one. **Design:** see [`DESIGN.md`](DESIGN.md) — implement to that document.

## Status

Steps **0–4** done: scaffold, emulator, ca65-subset assembler, YAML build/pack, Runix `rotoskop` branch (golden bins/`.2mg`, bootstub, `rotoskop run --profile`). **Next:** app shell + Git (§7, §1).

## Layout

| Path | Role |
|------|------|
| `DESIGN.md` | Product/architecture design (source of truth) |
| `Package.swift` | SwiftPM: `RotoskopCore` library + `rotoskop` CLI |
| `Sources/RotoskopCore` | Emulator, assembler, build/pack, run session |
| `Sources/rotoskop` | Mac CLI (`build`, `assemble`, `run`) |
| `Tests/RotoskopCoreTests` | Unit/integration tests (no UI) |
| `Apps/` | iOS app shell (step 5; placeholder) |
| `for_ref/runix` | Local symlink to Runix (gitignored) |

## Build & test (Mac)

Requires Xcode (Swift 6+).

```bash
swift build
swift test
swift run rotoskop --help
```

### Against Runix

```bash
RUNIX=/path/to/runix   # rotoskop branch
swift run rotoskop build "$RUNIX"
swift run rotoskop run "$RUNIX" --profile halt -v --screen
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
