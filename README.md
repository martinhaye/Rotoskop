# Rotoskop

Bespoke mini IDE for 6502 assembly targeting a simplified Apple II/III-style emulator. Offline-first, occasional GitHub sync. Primary project: [Runix](for_ref/runix) (via `rotoskop` branch once set up).

**Audience:** one. **Design:** see [`DESIGN.md`](DESIGN.md) — implement to that document.

## Status

Scaffold + emulation core + assembler in progress. Later: build system → app UI (see *Implementation order* in `DESIGN.md`).

## Layout

| Path | Role |
|------|------|
| `DESIGN.md` | Product/architecture design (source of truth) |
| `Package.swift` | SwiftPM: `RotoskopCore` library + `rotoskop` CLI |
| `Sources/RotoskopCore` | Shared core (emulator now; assembler/build later) |
| `Sources/rotoskop` | Mac CLI (`rotoskop run`, later `build`) |
| `Tests/RotoskopCoreTests` | Unit/integration tests (no UI) |
| `Apps/` | iOS app shell (step 5; placeholder for now) |
| `for_ref/runix` | Frozen upstream Runix + pim65 reference (local; gitignored) |

## Build & test (Mac)

Requires Xcode (Swift 6+).

```bash
swift build
swift test
swift run rotoskop --help
```

### Emulator CLI

```bash
swift run rotoskop run path/to/config.json \
  [--trace] [-n N] [--screen] [--keys STRING] [--disk image.2mg]
```

### Assembler CLI

```bash
swift run rotoskop assemble path/to/file.s -o out.bin -I include/dir [--list out.lst]
```

Assembles a ca65 subset straight to a raw binary (no linker). Byte-comparable with runix’s ca65+ld65 pipeline for boot, kernel, shell, bins, and runes tested so far.

## Reference

| Path | Role |
|------|------|
| `DESIGN.md` | Design |
| `for_ref/runix` | Frozen Make/ca65 golden builds |
| `for_ref/runix/pim65` | Python emulator this Swift core ports/improves |

## License / ownership

Personal project.
