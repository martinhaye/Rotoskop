# Implementation gaps (as of 2026-07-18)

Status after steps **0–4** of `DESIGN.md` *Implementation order*. Assembler golden and `.2mg` packer parity are closed for the runix `rotoskop` branch. Remaining polish is optional boot/run wiring before iOS shell work.

**Repos:** Rotoskop repo `/Users/mhaye/AppleII/Projects/Rotoskop` (`main`). Runix daily-driver branch is `rotoskop` at `/Users/mhaye/AppleII/Projects/runix` (symlinked as `for_ref/runix`). ca65/ld65 at `/Users/mhaye/AppleII/Projects/cc65_src/bin`.

---

## 1. Assembler vs ca65 — closed

Acceptance bar (§4.5): byte-comparable binaries vs ca65+ld65 for runix modules.

### Matching (all previously failing units now green)

| Unit | Notes |
|------|--------|
| `src/boot/boot.s` | Match |
| `src/kernel/kernel.s` | Match |
| `src/shell/shell.s` | Match |
| `src/bin/*` (halt, echo, ls, cd, pwd) | Match |
| `src/runes/02-font.s`, `03-bcd.s`, `05-pool.s` | Match (font via `build/generated/base_font.s`) |
| `src/rtest/testbcd1.s`, `testbcd2.s` | Match |
| `src/demos/aoc1a.s`, `aoc1b.s` | Match |
| Other `src/demos/*`, `src/rtest/*` in `rotoskop.yaml` | Match via full build |

### Fixes applied

1. **Comparison operators in expressions** — lexer/`ExprParser` now support `=`, `<>`, `<`, `>`, `<=`, `>=` (ca65 `BoolExpr`). Without this, `.if .paramcount >= 5` in `call` was always true (parsed as just `.paramcount`), so `mov`/`ldax` arg setup never ran.
2. **`brk n` signature byte** — ca65 `brk 0` emits `$00 $00`; bare `brk` stays one byte. Missing signature bytes shifted all later labels in aoc demos (looked like zp-vs-imm at first glance).

**Reproduce (should `cmp` clean):**

```bash
export PATH="/Users/mhaye/AppleII/Projects/cc65_src/bin:$PATH"
RUNIX=/Users/mhaye/AppleII/Projects/runix
RS=/Users/mhaye/AppleII/Projects/Rotoskop

(cd "$RS" && swift run -c release rotoskop assemble "$RUNIX/src/rtest/testbcd1.s" -I "$RUNIX/src/include" -o /tmp/u-rs.bin)
ca65 -t none -I "$RUNIX/src/include" -o /tmp/u.o "$RUNIX/src/rtest/testbcd1.s"
ld65 -C "$RUNIX/runix.cfg" -o /tmp/u-ca65.bin /tmp/u.o
cmp /tmp/u-rs.bin /tmp/u-ca65.bin
```

---

## 2. Disk image vs Make golden — closed

`rotoskop build` on the runix `rotoskop` branch produces a **byte-identical** `.2mg` to Make’s `build/runix.2mg` when bins match.

### Packer fix

- `pack_image` `dirs:` / `root:` key order is preserved (Yams `Node` mapping order).
- Previously `dirs.sorted(by: key)` alphabetized to `bin, demos, rtest, runes`, shifting every block after the root directory vs mkrunix’s `runes, bin, demos, rtest`.

**Verify:**

```bash
# Make golden, then Rotoskop overwrite build/, then cmp
(cd /Users/mhaye/AppleII/Projects/runix && make clean && make)
cp -a build /tmp/runix-make-golden
/Users/mhaye/AppleII/Projects/Rotoskop/.build/release/rotoskop build /Users/mhaye/AppleII/Projects/runix
cmp /tmp/runix-make-golden/runix.2mg /Users/mhaye/AppleII/Projects/runix/build/runix.2mg
# Also: cmp each build/**/*.bin against /tmp/runix-make-golden/
```

---

## 3. Runix `rotoskop` branch — leftover polish

Branch exists and builds (`rotoskop.yaml`, `font_to_asm.js`, font via `build/generated/`). Still open vs design step 4:

- [ ] Wire **bootstub** + richer `run:` / `profiles:` so `rotoskop run` can boot the image like pim65 tests (yaml already has a minimal `run:` + `halt` profile).
- [x] Prove **byte-compare** on all bins + image once assembler gaps are closed.
- [ ] Decide whether Make remains co-installed on the branch until cutover (design: yes until merge to `main`).

---

## 4. Out of scope for the gap-fix pass

Do **not** start unless gaps above are closed (or explicitly requested):

- Step 5+ iOS app shell / Git / editor (§7, §1–3)
- libgit2, PAT UI, TextKit, etc.

---

## Suggested test plan (regression)

1. `swift test` in Rotoskop (60+ tests).
2. Unit assemble: `testbcd1` / `testbcd2` / `aoc1a` / `aoc1b` vs ca65+ld65.
3. Full `rotoskop build` on runix `rotoskop`; `cmp` each `build/**/*.bin` and `runix.2mg` to a fresh Make golden.
