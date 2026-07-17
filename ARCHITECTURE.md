# Rotoskop — Architecture

This document sketches the overall structure and the reasoning behind it, before
we dive into per-component detail. It's a living document; expect it to evolve as
each component is fleshed out.

## Goals & constraints

- **Audience of one.** No multi-user concerns, no accounts. Simplicity wins over
  generality every time.
- **Offline-first.** The app must be fully usable with no network. Git sync is
  an occasional, explicit action — never on the hot path.
- **Develop & test on Linux.** As much logic as possible is written as
  platform-agnostic Swift so it compiles and is unit-tested with
  `swift build` / `swift test` in a Linux sandbox (and in CI), independent of
  Xcode, a simulator, or a device.
- **Small dependency footprint.** Prefer the standard library and Foundation.
  Moderate, well-scoped dependencies (e.g. a git binding) are acceptable where
  re-implementing would be wasteful; large frameworks are avoided.

## The core idea: logic in a SwiftPM package, UI in a thin app

The single most important structural decision is the split between:

1. **`Rotoskop` Swift package** (`Package.swift`, `Sources/`, `Tests/`) —
   contains *only* platform-agnostic library code. **Nothing here imports UIKit
   or SwiftUI.** This is what builds and tests on Linux.
2. **iOS app** (`App/`) — a thin SwiftUI layer that depends on the package via a
   local path dependency. It supplies the platform-specific pieces (views, the
   real file system, the real git implementation, the Keychain, etc.) by
   conforming to protocols defined in the package.

This keeps the interesting, bug-prone logic (a CPU emulator, file operations,
sync-state math) under fast, deterministic tests, and relegates the app target
to wiring and presentation.

```
┌──────────────────────────── App/ (Xcode, iOS only) ───────────────────────────┐
│  SwiftUI views · UITextView editor · FileManager FS · libgit2 · Keychain      │
└───────────────┬───────────────────────────────────────────────────────────────┘
                │ depends on (local path), injects concrete impls
┌───────────────▼──────────────── Rotoskop package (Linux-testable) ─────────────┐
│  RotoskopEmulator   RotoskopWorkspace   RotoskopGit   RotoskopEditorCore        │
└────────────────────────────────────────────────────────────────────────────────┘
```

### Why not put the app in `Package.swift`?

Because an iOS app target (or any UIKit/SwiftUI code) can't build on Linux, and
we want `swift build`/`swift test` to Just Work in the sandbox. Keeping the
package UI-free is the price of Linux testability, and it's a good price: it
enforces a clean separation of concerns.

## Components → modules

The four product components map onto library targets:

| Product component        | Module               | Linux-testable? | Notes |
|--------------------------|----------------------|-----------------|-------|
| Emulation core           | `RotoskopEmulator`   | ✅ fully        | Pure computation. The current focus. |
| File browser             | `RotoskopWorkspace`  | ✅ (via fakes)  | Logic behind a `FileSystem` protocol. |
| Repo list / push / pull  | `RotoskopGit`        | ✅ (via fakes)  | Protocol + value types; real impl in app. |
| Code editor              | `RotoskopEditorCore` | ✅ (model only) | Document/buffer model; view in app. |

The pattern for the three "I/O" components is the same: **define a protocol +
value types in the package, provide an in-memory/fake implementation for tests,
and inject the real (Foundation/UIKit/libgit2-backed) implementation from the
app.** `RotoskopWorkspace.FileSystem` + `InMemoryFileSystem` is the reference
example.

### 1. `RotoskopEmulator` (focus)

A cycle-counting NMOS 6502 wired to a simplified Apple II/III memory map, with
debugging and text-screen decoding. Pure Swift, no Foundation except a small
formatting use in the disassembler. Key types:

- `CPU6502` — register file, fetch/decode/execute loop, operand resolution for
  all 13 addressing modes, stack, interrupts, cycle accounting.
- `MemoryBus` (protocol) — everything the CPU addresses sits behind this. `RAM`
  is a flat 64K implementation; `AppleMemoryMap` is the simplified machine map
  (named regions today; soft-switches / ROM / MMIO later).
- `InstructionSet` — builds the 256-entry opcode dispatch table. **This is the
  primary porting seam** (see below). Behaviour is factored into reusable
  helpers in `Instructions.swift` (loads, ADC/SBC, compares, shifts, branches…),
  so table entries are declarative.
- `TextScreen` — decodes the interleaved Apple II 40×24 text page into strings.
- `Disassembler` — shares the exact opcode table with the CPU, so they can't
  drift; used by the debugger view and tests.
- `Machine` — the "virtual Apple" façade: owns CPU + memory, loads programs,
  runs with breakpoint and cycle/instruction budgets, exposes register
  snapshots and the rendered screen.

**Testability model:** deterministic, no wall-clock or threads. Tests assemble
tiny byte programs, run them, and assert on registers, memory, cycles, and the
decoded screen. `Machine.run(...)` takes explicit budgets so runaway programs
can't hang a test.

**Porting the Python core:** the intended workflow is to translate the existing
Python 6502 into `InstructionSet.buildTable()` (and, where needed, new helpers
in `Instructions.swift`). The scaffolding here — addressing-mode resolution,
flag helpers, stack/vector plumbing, cycle counting — is exactly the shared
substrate those handlers need, so porting is mostly "for each opcode, pick a
mode + cycles + helper." The current table implements a representative slice
(every instruction family) to prove the machinery end-to-end; completing it
(and deciding whether to include unofficial opcodes and exact decimal-mode
flag quirks) is the next step once the Python source is in hand.

### 2. `RotoskopWorkspace`

The file-browser's model and operations behind a `FileSystem` protocol.
`WorkspacePath` is a platform-neutral, root-relative path type; `FileEntry`
describes listings. `InMemoryFileSystem` backs tests/previews. The app will add
a `FoundationFileSystem` (FileManager-backed, scoped to each repo's checkout
directory). Foundation's FileManager is available on Linux too, so even the real
implementation could eventually be exercised in the sandbox if useful.

### 3. `RotoskopGit`

Repo list + sync. Only the abstraction lives in the package: `Repository`,
`SyncStatus`, `GitCredentials`, `GitError`, and the async `GitService` protocol
(`clone`/`status`/`pull`/`push`/`commitAll`). View-model logic can be tested
against a fake conforming to `GitService` (see `GitModelTests`).

The concrete implementation is an app-layer decision deferred until we design
this component. Likely options: **SwiftGit2 / libgit2** (moderate dependency,
full-featured, works on iOS) is the current front-runner; a pure-Swift git or
shelling out are alternatives. Credentials come from the Keychain in the app.

### 4. `RotoskopEditorCore`

The editor view itself will be a `UITextView` subclass in the app with iOS
"conveniences" disabled (autocorrect, smart quotes/dashes, autocapitalisation,
predictive text, etc.) — the things that make typing code painful. The
package-side `TextDocument` holds the buffer and line-index bookkeeping shared
by the editor and emulator tooling (e.g. mapping an assembler error offset to a
line). Future package-side additions: a 6502 assembler + tokenizer so the
edit → assemble → run → inspect loop is closed and fully testable on Linux.

## Data & control flow (target design)

```
Repo list ──select──▶ File browser ──open──▶ Editor
   │(RotoskopGit)        │(RotoskopWorkspace)   │(RotoskopEditorCore)
   │                     │                      │ assemble (future: RotoskopAssembler)
   ▼                     ▼                      ▼
 push/pull            file ops             bytes ──load──▶ Machine (RotoskopEmulator)
                                                              │ run / step / breakpoints
                                                              ▼
                                                    registers · memory · text screen
                                                        (Debugger UI in app)
```

State management in the app will use SwiftUI + `@Observable`/`ObservableObject`
view models that own the injected services; the package types are plain
value/reference types with no framework coupling.

## Testing strategy

- **Unit tests in the package** cover all core logic and run on Linux in CI.
- **I/O components** are tested through their protocols with in-memory fakes.
- The emulator will additionally benefit from **program-level tests** (assemble
  or hand-assemble a routine, run it, assert on the resulting machine state),
  and can later be validated against standard 6502 test suites (e.g. Klaus
  Dormann's functional tests) once the instruction table is complete.

## Roadmap (order, not dates)

1. **Emulator core** — port the Python 6502 into the dispatch table; flesh out
   the Apple II/III memory map (soft-switches, ROM), and the debugger surface.
2. **Assembler** (`RotoskopAssembler`) — close the edit→run loop, Linux-tested.
3. **Workspace + editor** — file browser and the stripped-down editor view.
4. **Git sync** — pick and integrate the concrete `GitService` implementation.
5. **App shell** — navigation tying the components together, on-device polish.

## Dependency policy

- Default to the standard library + Foundation.
- The emulator, workspace, and editor cores currently have **zero external
  dependencies**.
- Anticipated moderate dependency: a git binding (libgit2/SwiftGit2) in the app
  layer only. Anything larger gets discussed first.
```
