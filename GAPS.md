# Implementation gaps (as of 2026-07-18)

Status after **design implementation order steps 0–4**. Assembler golden, `.2mg` packer parity, bootstub, and yaml-driven `rotoskop run --profile` are closed. Next work is step 5 (iOS app shell)—not started.

**Repos:** Rotoskop `/Users/mhaye/AppleII/Projects/Rotoskop` (`main`). Runix daily-driver branch `rotoskop` at `/Users/mhaye/AppleII/Projects/runix` (`for_ref/runix`). ca65/ld65 at `/Users/mhaye/AppleII/Projects/cc65_src/bin`.

---

## 1. Assembler vs ca65 — closed

Byte-comparable vs ca65+ld65 for runix modules (including `testbcd*`, `aoc1*`, boot/kernel/shell/bin/runes).

**Fixes:** expression compares (`=`, `<>`, `<`, `>`, `<=`, `>=`) for `.paramcount` in `call`; ca65-style `brk n` signature byte.

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

`rotoskop build` produces a **byte-identical** `.2mg` to Make when bins match. Packer preserves YAML `dirs:` / `root:` key order (mkrunix: runes, bin, demos, rtest).

```bash
(cd /Users/mhaye/AppleII/Projects/runix && make clean && make)
cp -a build /tmp/runix-make-golden
# Note: Make does not build bootstub; compare packed image after rotoskop build
# using bins from Make, or cmp bins individually then pack-only.
/Users/mhaye/AppleII/Projects/Rotoskop/.build/release/rotoskop build /Users/mhaye/AppleII/Projects/runix
cmp /tmp/runix-make-golden/runix.2mg /Users/mhaye/AppleII/Projects/runix/build/runix.2mg
```

---

## 3. Runix `rotoskop` branch — closed

- [x] **bootstub** — `tests/bootstub.s` assembles to `build/bootstub.bin` (same bytes as `tests/mkbootstub.py`). Wired in `run.load`.
- [x] **`rotoskop run` + profiles** — project root / `rotoskop.yaml`; `--profile halt|pwd|ls|testbcd1|testpool`. YAML real newlines map to Apple II CR.
- [x] **Byte-compare** on bins + image (see §1–2).
- [x] **Make co-installed until cutover** — yes (design: keep Make/ca65/`mkrunix.py` as golden on the branch until `rotoskop` → `main`). Do not remove Makefile yet.

Prove boot:

```bash
rotoskop build /path/to/runix
rotoskop run /path/to/runix --profile halt -v --screen   # exit 0 at $FFF9
rotoskop run /path/to/runix --profile pwd --screen
```

---

## 4. Out of scope until requested

- Step 5+ iOS app shell / Git / editor (§7, §1–3)
- libgit2, PAT UI, TextKit, etc.

---

## Suggested regression

1. `swift test` in Rotoskop (61+ tests).
2. Unit assemble golden samples vs ca65+ld65.
3. Full `rotoskop build` + `cmp` bins/`.2mg` to Make golden.
4. `rotoskop run --profile halt` (and optionally `pwd` / `ls`).
