# Rotoskop — Design Document

Status: **design complete** (all major sections agreed; Runix incorporation agreed). Ready to implement to this document.

## Purpose

Rotoskop is a bespoke mini IDE for developing 6502 assembly that targets a simplified Apple II/III emulation core. Primary audience: one person (the author). Work is offline-first; GitHub sync is occasional, not continuous.

The motivating project is **runix** (`for_ref/runix`): a bare-metal Apple III OS in 6502 assembly. Rotoskop should be able to edit, assemble, build a `.2mg` disk image (plus small ROM bits), and run/debug that image in-emulator.

## Constraints & Lessons

- **Mac-native development.** Build and iterate on the Mac with Xcode (and whatever else is needed). Do not structure the project around a Linux/cloud-compileable subset vs an iOS-only shell. That split dominated the first attempt and made everything painful.
- **Design before code.** This document comes first. Implement only after the section being built is sufficiently specified.
- **Avoid large dependencies.** Moderate ones are fine; prefer small, understandable pieces over frameworks that own the architecture.
- **Swift throughout**, including the emulator, assembler, and build system—so the same logic can eventually sit behind the iOS UI without a second implementation.

## Major Pieces

### 1. Repo list & Git

**Agreed** for v1. Offline-first project list backed by **app-managed git clones**, with enough GitHub sync to commit / branch / merge-cleanly / push / pull—not a full Git GUI.

#### 1.1 Project list

- List of known repos; open one → file browser / rest of the IDE.
- **Add = clone** from a GitHub remote URL (HTTPS) into an **app-managed directory** (not “pick any folder”).
- **Remove** from the list **and delete** the local clone (confirm first). No orphan checkouts outside app storage in v1.
- Coding works fully offline; network only for clone / push / pull (and auth setup).

#### 1.2 Git operations (in-app)

| Operation | v1 behavior |
|-----------|-------------|
| **Status** | Enough to commit usefully (changed/new/deleted file list; diff viewer polish optional) |
| **Commit** | Stage relevant changes (v1: all changes or simple file picker—keep dumb) + message → commit |
| **Push / Pull** | Explicit actions when online |
| **Branch** | Create / switch branch |
| **Merge** | Merge only if **clean** (fast-forward or auto-merge with no conflicts). On any conflict: **abort**, leave repo as before, show a clear message. No conflict editor, no fancy merge tooling |

Out of scope: rebase, cherry-pick, stash UI, submodule management, LFS, blame, in-app conflict resolution.

#### 1.3 Auth

- **v1: GitHub Personal Access Token stored in Keychain**, used for HTTPS clone/push/pull.
- Audience of one: simplest reliable path; rotate/replace token in a settings field when needed.
- **OAuth / “Sign in with GitHub”** deferred—better product polish, more moving parts (app registration, redirect, refresh). Revisit if PAT friction becomes annoying.
- Token scopes: sufficient for private repo clone/push (classic `repo` or fine-grained equivalents).

#### 1.4 Implementation note

- iOS has no system `git` binary → use a **libgit2**-based Swift stack (moderate dependency), shared with any Mac CLI that needs the same ops.
- Remotes assumed GitHub HTTPS for v1; SSH optional later.

#### 1.5 Deferred / tune in UI

- Exact commit staging UX (commit all vs pick files).
- Whether pull is merge or rebase-never (merge-only, consistent with §1.2).
- Fine-grained vs classic PAT instructions in the auth UI copy.
### 2. File browser

**Agreed** for v1. Separate from the editor (opens files into it, but is its own surface).

- Project tree for day-to-day file/dir work: create, rename, move, delete; open → editor.
- **Show `build/`** (listings, binary sizes, artifacts).
- **Hide `.git/`** (never useful in-app).

*(Further browser chrome can follow the app shell.)*

### 3. Code editor

**Agreed** for v1. Plain-text code editor: proportional font, tab-stop layout for assembly, autosave always, and almost no iOS text-widget specialness. Implementation may be a custom text view or a fully disarmed TextKit stack—whichever gets the gesture model right with less pain.

#### 3.1 File kinds

| Kind | Extensions (v1) | Tab stops | Space / Enter | Highlighting |
|------|-----------------|-----------|---------------|--------------|
| Assembly | `.s`, `.i` | Fixed semantic columns (tunable M-widths) | §3.3 | Simple asm |
| Non-assembly | everything else | Fixed interval, every **4 M-widths** (tabs still display on stops if present) | Space = ` `; Enter auto-indents (§3.3) | None |

#### 3.2 Typography & layout

- **Proportional font** (author preference). Exact face TBD; prefer clear `O`/`0`, `l`/`1`.
- **No soft wrap.** v1: **truncate** on the right (horizontal scrolling may come later).
- Tab stops are **fixed** (not elastic); assembly column positions tunable for feel.

#### 3.3 Tabs, spaces, Enter

**Assembly — columns** are only “text after N tabs.” No smart classification; tab count chooses the column.

**Assembly — Space key:**
- Inside quotes → ` `
- Immediately after a comma → ` `
- In a comment body (cursor after `;` on that line) → ` `
- Otherwise → `\t`

**Assembly — Tab key:** always `\t`.

**Non-assembly — Space:** always ` ` (no Space→tab). YAML-safe.

**Non-assembly — Enter:** insert newline, then copy the **leading whitespace** (spaces/tabs) of the previous line (auto-indent); backspace clears it as usual.

**Assembly — Enter:** plain newline, no auto-indent in v1.

#### 3.4 Syntax highlighting

- Assembly only, simple (comments, directives, opcodes, numbers, strings, labels—palette TBD).
- No JS/YAML highlighter in v1.

#### 3.5 Persistence & diagnostics

- **Autosave always** (debounce at implementation).
- **Build errors in context:** when a build/assemble diagnostic points at a file/line (and column if known), the Editor can show it **in place**—e.g. highlight/mark the line and surface the message near the caret or in a compact banner—not only as a log line on the Build tab. Jump-from-Build and in-editor display share the same diagnostic.

#### 3.6 Touch & editing chrome

Disable spell check, autocorrection, autocapitalization, smart quotes/dashes, loupe/hold-to-select, shake-to-undo, and other system text “helps.”

| Gesture | Action |
|---------|--------|
| **Tap** | Position cursor |
| **Slow drag starting near the cursor** | Move cursor precisely |
| **Quick flick, or drag starting well away from the cursor** | Scroll |
| **Once scrolling has begun** | Remain scrolling until finger lifts |

**`⋯` menu:** Select, Select All, Cut, Copy, Paste, Undo (Redo if cheap). Hardware shortcuts (Cmd-C/V/X/A/Z, etc.) still work.

**Select mode (v1):**
1. **Select** enters select mode with an initial range: keep any existing selection; else select the **word** at the cursor (if none, empty selection—drag to define a range).
2. In select mode, **drag** adjusts the range; **tap** reanchors simply (tune in UI).
3. **Select All** selects the whole document.
4. **Cut / Copy** use the selection and **exit** select mode. **Paste** replaces selection or inserts at cursor; exits select mode.
5. Dismiss via **⋯** / Escape / explicit cancel without copying.
6. No drag-handles required for v1; add later if needed.

Scroll vs select: flick/far-drag still **scrolls**; selection persists while scrolling.

#### 3.7 Deferred

- Exact assembly tab-stop positions; near-cursor / flick thresholds (tune in UI).
- Horizontal scrolling; trackpad/pointer parity; Redo if not free with Undo.

### 4. Assembler (ca65 subset)

A Swift assembler implementing a **runix-complete subset of ca65**—enough to assemble runix as it stands, not a full ca65 clone. No separate linker: **assemble straight to a raw binary**.

Reference: runix sources under `for_ref/runix/src`, especially `include/base.i` for macros; ca65 docs only as needed to match observed behavior.

#### 4.1 Output model

- **One source file → one raw binary** (plus optional listing).
- **No object files, no ld65, no multi-unit link.** Runix never links multiple `.o` files together today; each module is already a self-contained assemble→binary step.
- Intended load/base address comes from **`.org`** in the source (as runix does now).
- **Listing (`.lst` or equivalent)** is required: needed to verify macro expansion / emitted bytes. The app UI must be able to show listings; details deferred to the app-shell / editor sections.

#### 4.2 In scope (driven by runix usage)

**CPU / instructions**

- Official **6502** only (no 65C02 / 65816).

**Directives / data**

- `.byt` / `.byte`, `.word`, `.res`, `.align` (including fill byte, e.g. `.align 32,$EA`)
- String literals in data; **`.feature string_escapes`** (`\n` etc.)
- `.org`, `.include`, `.error`
- `.proc` / `.endproc`
- Equates: `name = expr`

**Labels**

- Named labels
- Cheap locals (`@name`)
- Unnamed labels (`:`, `:+`, `:-`)
- Scoped refs into procs (`proc::label`)

**Macros & compile-time logic** (the hard part; implement only what runix needs)

- `.macro` / `.endmacro`, `.local`, `.paramcount`
- Conditionals: `.if` / `.elseif` / `.else` / `.endif`
- Token/pseudo-functions used by runix macros: `.match`, `.xmatch`, `.left`, `.right`, `.tcount`, `.strlen`, `.ident`, `.concat`, `.string`
- Enough expression/`#`/`</>`/`1+(addr)` support for runix idioms
- The `&label` form in macros (e.g. `ldax`) is a **runix macro convention** (with `cld` as relocator marker), not a general ca65 addressing mode—support it insofar as those macros require

**Includes**

- Include search path(s) equivalent to ca65 `-I` (runix uses `src/include`)

#### 4.3 Out of scope (v1)

- Object format, imports/exports, multi-file linking
- `.segment` / `.code` / `.data` / `.bss` / `.rodata` workflow (runix uses `.org` instead)
- `.struct` / `.enum` / `.scope` / `.repeat` / `.define` / `.set` / `.incbin` / `.macpack`
- 65C02 / 65816, far addresses, constructors/destructors, ca65 debug info
- Full ca65 macro language beyond what runix actually uses
- Being bug-compatible with every ca65 corner case—**runix assembles correctly** is the acceptance bar

#### 4.4 Errors & IDE

- Assembler errors must be reportable with file/line (and preferably column) so the IDE can surface them.
- Exact diagnostic format TBD with the app shell; content must be machine-usable, not only human CLI text.

#### 4.5 Acceptance

- Assembling runix sources produces binaries equivalent to the current ca65+ld65 pipeline for those units (byte-comparable for normal modules; listings available for diagnosing macro differences).

### 5. Build system

Replace Makefile-centric workflow with a **YAML** project config: an **ordered pipeline of typed steps** that assemble modules and produce a bootable **`.2mg`** (and supporting run artifacts). No Make, no linker. Same engine for **CLI and in-app UI** (phone ↔ Mac terminal).

Consumed: assembler (§4). Produces artifacts the emulator (§6) can run (private copy of the disk at run time).

References: `for_ref/runix/Makefile`, `mkrunix.py` (packer logic to port); `runix.cfg` obsolete given assemble-to-binary.

#### 5.1 Decisions

- **Config file:** `rotoskop.yaml` at the project root.
- **Config language: YAML** (modest dep such as Yams).
- **v1: full rebuild** — run the step list top to bottom; no incremental graph.
- **No linker** — assemble to raw `.bin`, then pack (§4).
- **Hosting: CLI + library/UI** — one implementation, two fronts.
- **CLI:** `rotoskop build [project-root]` (default `.`); shared diagnostics with the UI. Remote deploy **out of scope**.
- **Shape: ordered typed steps**, not an embedded programming language for the pipeline itself.
- **Global `include_dirs`** for assemble steps.
- **v1 step kinds:**
  - `assemble` — source(s)/glob → `.bin` (+ listing)
  - `generate` — JS script → generated file via stdout (see below)
  - `pack_image` — parameterized packer; first format `runix_2mg`
- **`pack_image` / `runix_2mg`:** Produce a **real `.2mg`** (ProDOS-order, proper header—mkrunix semantics) usable in any Apple II emulator. **ROM bits are not inside the `.2mg`.** Slot-2 HD ROM is **emulator-synthesized** (4th-wall device intercept)—not a build output. Other run helpers (e.g. boot stub) may still be normal assemble outputs referenced from `run:`.
- **`generate` (v1):** **JavaScript** via JavaScriptCore. Step sets `language: js` so other languages can be added later. **No Python runtime.**
  - Script **stdout is the generated file** (written to the step’s `out:` path).
  - Tiny host API (JSC, not a browser): **`print(...)`** appends to that stdout; **`read(path)`** reads a project-relative input (e.g. font text). Optionally alias `console.log` → `print`.
- **Generated sources (v1):** Write generate outputs under **`build/generated/`** (e.g. `build/generated/base_font.s`). That directory is **auto-added to the assemble include path**. Assemblable units are only what `assemble` steps list/glob under `src/` (etc.)—do **not** glob `build/generated/` as top-level assemble inputs. Hand-written code `.include`s the generated file by basename. Iterate later if we need excludes or in-tree generate outs.
- **Build + run in one file, with overlays for tests** — see §5.2.

#### 5.2 Build + run config (one file, overlays for tests)

Keep **one `rotoskop.yaml`** with both a build pipeline and a **default `run:`** profile (CLI `rotoskop run` and the app).

**Why overlays:** automated tests share disk/boot setup but vary **keys**, **max instructions**, and sometimes **loads**.

**Model:**

- **Base:** `rotoskop.yaml` → `steps:` + default `run:`.
- **Overlay:** shallow merge of run-related fields. Via named **`profiles`** (`rotoskop run --profile halt`) and/or external/in-memory overlays for the test harness.

**Default `run:` fields (v1):**

| Field | Role |
|-------|------|
| `disk` | Path to `.2mg` (optional if running a bare binary) |
| `load` | List of `{ file, addr }` binaries to load before start |
| `start` | Reset/start address (PC) |
| `max_instructions` | Cap for CLI/tests (optional in interactive app) |
| `keys` | Scripted keyboard strings (CLI/tests; app uses interactive input) |
| `trace` | Instruction trace on/off |
| `screen` | Dump text screen on exit (CLI) |

Profiles/overlays may override any of the above. Stop reasons remain those in §6.5.

Illustrative shape:

```yaml
name: runix
include_dirs: [src/include]
build_dir: build

steps:
  - generate:
      language: js
      script: src/runes/font_to_asm.js
      out: build/generated/base_font.s

  - assemble:
      sources: src/boot/boot.s
      out: boot.bin

  - assemble:
      sources: src/runes/*.s    # does not pick up build/generated/
      out_dir: runes/

  - pack_image:
      format: runix_2mg
      out: runix.2mg
      boot: boot.bin
      root:
        runix: kernel.bin
      dirs:
        runes: runes/*.bin
        bin: [shell.bin, bin/*.bin]
        demos: demos/*.bin
        rtest: rtest/*.bin

run:
  disk: build/runix.2mg
  load:
    - { file: tests/bootstub.bin, addr: 0x1000 }
  start: 0x1000
  max_instructions: 100000

profiles:
  halt:
    keys: ["halt\n"]
```

#### 5.3 Status

**Agreed** for v1. Generated-path convention and `run:` field set may get minor tweaks in implementation without reopening the section’s shape.
### 6. Emulation core

Swift 6502 + simplified Apple II-ish environment, modeled on **pim65** (`for_ref/runix/pim65`), with targeted improvements. Same core powers a **CLI** (scripted / test-oriented) and an **in-process library** heavily wired into the app UI.

Reference: pim65’s CPU, memory, simulator, Apple II helpers, JSON load config, and CLI.

#### 6.1 CPU

- Official 6502 opcode set; **results-accurate**, not cycle-accurate.
- BCD ADC/SBC; classic JMP (`$xxFF`) page-wrap bug.
- `step` and bounded `run` (instruction limit remains useful for CLI/tests).
- Clean halt when PC reaches **`$FFF9`** (cc65-conventional success/halt; used by runix `halt` and tests).
- **Illegal opcode** → stop + dump (registers, PC, recent context as available).
- No emulator-level breakpoints. Debugging uses the 6502 **`BRK`** mechanism (and runix’s own handler when installed).
- **Unhandled BRK:** if a `BRK` is executed while the IRQ/BRK vector (`$FFFE`/`$FFFF`) is **unset**, stop + dump. A vector is **set** once it has been **written** since reset; until then it is unset (regardless of the `$FF` fill value). If set, normal 6502 BRK behavior (push state, jump via vector)—including runix string macros and `BRK $00` → kernel breakpoint path.
- Instruction **trace** (disassemble + register/flag line) available for CLI and optional library use.
- **PC hooks** retained (e.g. hard-drive entry intercept). Not a general breakpoint UI.

#### 6.2 Memory

- **v1: flat 64KB**, initialized to `$FF`.
- Per-address **read/write hooks** for soft-switches / I/O.
- Load binary at address; set reset vector; word R/W; ZP-wrapping word read.
- **Dump bypasses hooks** (inspection must not trigger I/O).
- **Leave room for future banking.** Apple II and Apple III bank strategies diverge wildly; v1 API/structure should not paint us into a single-bank-forever corner, but banking itself is out of scope for v1.

#### 6.3 Display & input

- **Text screen (v1):** 40-column only; decode `$400–$7FF` Apple II layout to a trimmed string (hi-bit ASCII → printable), as in pim65.
- **Keyboard — CLI / tests:** scripted input strings (C-style escapes; `\n` → CR), via `$C000` / `$C010`.
- **Keyboard — app mode:** **interactive**; UI feeds keystrokes into the same soft-switch model while the emulator runs.

#### 6.4 Disk

- Slot-2 ProDOS **block device** over `.2mg` (64-byte header + 512-byte blocks), with **emulator-synthesized** slot ROM signatures and PC intercept at entry (pim65 model). Slot ROM is a 4th-wall device fiction—not a build artifact.
- **Do not mutate build artifacts in place.** At run start, take a **full private copy** of the `.2mg`; all runtime writes hit the copy. (Sparse base+overlay remains a possible later optimization; not required for v1.)

#### 6.5 Hosting: CLI vs library

- **Shared core** (CPU, memory, devices, load/run/stop/dump/screen).
- **CLI:** roughly pim65’s current shape (`--trace`, instruction limit, `--screen`, `--keys`, `--disk`, config of binaries + start). Config file format may be absorbed or superseded by the **build system** section later.
- **Library:** same engine, driven by the app. Emulation **run loop on a background thread** so the UI stays responsive. UI observes screen/regs/stop reasons and injects interactive keyboard input.
- **Stop reasons** the host can distinguish: success (`$FFF9`), instruction limit, unhandled BRK, illegal opcode, explicit stop/reset from UI, I/O errors.

#### 6.6 Intentionally deferred / out of scope (v1)

- Symbol-aware debugging (hard with runix’s dynamic relocation). Revisit if low-hanging opportunities appear (e.g. static boot/kernel symbols only).
- Emulator breakpoints beyond `BRK` / PC hooks for devices.
- Banked memory; 80-column / richer Apple III video; sound; floppy; SmartPort beyond the block path; free-running IRQ/NMI injection.
- Full Apple II/III monitor ROM. Guest jumps into missing monitor/ROM space → **stop + dump** for now. Real ROMs may be incorporated later if desired.

#### 6.7 Testability

- Unit-testable without the iOS UI (CPU, memory, devices, load/run scenarios).
- Able to support runix-style integration tests: boot stub + disk image + scripted keys + screen assertions.

### 7. App shell (iOS)

**Agreed** for v1. **iPhone portrait only.** Hosts repo list, files, editor, build, run, and git. No separate iPad layout; no Mac-in-app shell for v1 (Mac use is the CLI).

*Jargon: “chrome” here means the surrounding UI (tab bar, nav bar, buttons)—not a web browser.*

#### 7.1 Root: repo list

- List of cloned projects; open one → project shell.
- Add (clone), remove (delete local clone), Settings (PAT).

#### 7.2 Project shell (iPhone portrait)

Bottom tabs:

| Tab | Role |
|-----|------|
| **Files** | File browser; open a file switches to Editor |
| **Editor** | One open file at a time; switch files via Files; can show build errors in context (§3.5) |
| **Build** | Run the YAML pipeline; show log; tap errors → Editor at file/line; open listings under `build/` |
| **Run** | Emulator text screen, start/stop, interactive keyboard; stop reason / dump |

**Git** is not a fifth tab: a nav-bar button opens a Git sheet/screen—status, commit, branch, merge-if-clean, push/pull.

Project nav bar shows repo name + current branch when known; actions: **Git**, plus **Build** / **Run** shortcuts if useful in addition to tabs.

**Listings:** browse `build/*.lst` in Files, or jump from Build results. No separate listings mode.

**Run and build:** choosing **Run** **builds first if anything has changed** (sources/config vs last successful build outputs—exact dirty check at implementation). If the build fails, stay on diagnostics (Build tab and/or Editor in-context errors)—do not start the emulator. If up to date, skip straight to run.

**Defaults:** stay on Build after an explicit Build finishes (don’t auto-jump to Run). Run is a full tab of its own.

#### 7.3 Out of scope for v1 shell

- iPad-optimized / landscape-first layouts
- Multi-file editor tabs
- Floating or multi-window emulator
- In-app Mac UI

#### 7.4 Deferred / tune in UI

- Exact placement of Git / Build shortcuts on the nav bar vs tabs-only.
- Whether Run offers profile picker (`profiles:` from §5) in v1.
- Visual density of the shell (keep utilitarian).
- Dirty-detection details for Run-triggered build.

---

## Implementation discussion notes

### Runix incorporation — **agreed**

Runix is the grounding for assembler scope, byte-for-byte acceptance, and day-to-day playtesting.

- **One repo**, two eras—not two divergent OS forks.
- **Upstream / `main` (and `for_ref/runix`):** frozen reference. Keep the Make/ca65/`mkrunix.py` pipeline as the golden producer. Do **not** merge Rotoskop-era assembly work back into this frozen line.
- **`rotoskop` branch:** daily driver. Add `rotoskop.yaml`, JS generate (e.g. font), `build/generated/`, and only the minimal source tweaks needed for that layout. **All new Runix development happens here**, inside Rotoskop (and the matching git remote branch).
- **Equivalence:** while both pipelines exist, at a shared baseline of sources, build golden (old toolchain) vs candidate (Rotoskop) and compare `.bin` / `.2mg` (mind `.2mg` header fields).
- **Leave Make behind:** merge **`rotoskop` → `main`**. That cutover retires the old scaffolding as the trunk; no ongoing dual-merge of assembly fixes.

Rotoskop app clones track the **`rotoskop`** branch (until cutover, then `main`).

## Implementation order

Brief build sequence. Each step should be usable/tested before piling on the next. Details live in the sections above.

0. ~~**Scaffold**~~ — **done**
1. ~~**Emulation core (§6)**~~ — **done**
2. ~~**Assembler (§4)**~~ — **done**
3. ~~**Build system (§5)**~~ — **done**
4. ~~**Runix `rotoskop` branch**~~ — **done** (`rotoskop.yaml`, JS font, bootstub, run profiles; Make co-installed until cutover)
5. **App shell + repos/Git (§7, §1)** — iPhone portrait tabs; clone/list; PAT; thin Git ops.
6. **File browser + editor (§2–3)** — browser; custom/disarmed editor (tabs, gestures, highlighting); autosave; diagnostics in context.
7. **Integration** — Build/Run tabs, dirty Run→build, emulator UI keyboard, error jump, listings from `build/`.

Defer polish called out as “tune in UI” until the vertical slice works.

Steps **0–4** are complete and regression-green (assembler/image byte-compare vs Make/ca65; `rotoskop run --profile halt`). **Next: step 5.**

## Reference material

| Path | Role |
|------|------|
| `for_ref/runix` | Motivating project: sources, Makefiles, image builder, linker config |
| `for_ref/runix/pim65` | Python emulator to port/improve in Swift |
| `for_ref/runix/mkrunix.py` | How the `.2mg` filesystem image is built today |
| `for_ref/runix/runix.cfg` | ld65 memory/segment layout used by runix |

## Working process

1. Keep this document as the single design surface.
2. ~~Flesh out sections one at a time~~ — **done.**
3. Implement to this document; resist scope creep.
4. Prefer concrete decisions over inventing architecture ahead of need.

## Section backlog (order flexible)

1. ~~Emulation core~~ — **agreed** (§6)
2. ~~Assembler (ca65 subset)~~ — **agreed** (§4)
3. ~~Build system~~ — **agreed** (§5)
4. ~~Editor + file browser~~ — **agreed** (§2–3)
5. ~~Repo / Git sync~~ — **agreed** (§1)
6. ~~App shell / navigation~~ — **agreed** (§7)

**Design + Runix incorporation: complete.** Implementation order above.

---

*Ready to build.*
