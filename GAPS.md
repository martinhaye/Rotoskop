# Implementation gaps (as of 2026-07-18)

Status after steps **0–4** of `DESIGN.md` *Implementation order*. Emulator, assembler, build system, and Runix `rotoskop` branch exist; these are the known holes before trusting golden compares / moving on to the iOS shell.

**Repos:** Rotoskop repo `/Users/mhaye/AppleII/Projects/Rotoskop` (`main`). Runix daily-driver branch is `rotoskop` at `/Users/mhaye/AppleII/Projects/runix` (symlinked as `for_ref/runix`). ca65/ld65 at `/Users/mhaye/AppleII/Projects/cc65_src/bin`.

---

## 1. Assembler vs ca65 — failing units

Acceptance bar (§4.5): byte-comparable binaries vs ca65+ld65 for runix modules.

### Matching (regression floor — keep green)

Verified earlier / still the bar for “don’t break these”:

| Unit | Notes |
|------|--------|
| `src/boot/boot.s` | Match |
| `src/kernel/kernel.s` | Match |
| `src/shell/shell.s` | Match (needed cheap-local `@` fix) |
| `src/bin/*` (halt, echo, ls, cd, pwd) | Match |
| `src/runes/02-font.s`, `03-bcd.s`, `05-pool.s` | Match (with generated `base_font.s`) |

### Failing

| Unit | Symptom (rotoskop vs ca65+ld65) | Likely cause |
|------|----------------------------------|--------------|
| `src/rtest/testbcd1.s` | **Size** 816 vs **1328** | Nested macros under-expand: `bcd_load` → `ldstr` + `call`; `call` → `ldax`/`mov` with **`&label`** address-mode and `.paramcount` / `.ident(.concat(.string(func),"_arg0"))`. See `src/include/bcd.i`, `src/include/base.i` (`ldax`/`call`/`print`). |
| `src/rtest/testbcd2.s` | **Size** 1072 vs **2096** | Same family as testbcd1. |
| `src/demos/aoc1a.s` | Same size **19183**, **243** byte diffs; first @42: `A5` (LDA zp) vs `A9` (LDA #) | Wrong addressing-mode choice and/or expression/`#` handling amid large `.byt` data + unnamed labels. |
| `src/demos/aoc1b.s` | Same pattern as aoc1a (same-size, many diffs) | Same. |

**How to reproduce**

```bash
export PATH="/Users/mhaye/AppleII/Projects/cc65_src/bin:$PATH"
RUNIX=/Users/mhaye/AppleII/Projects/runix
RS=/Users/mhaye/AppleII/Projects/Rotoskop

# Rotoskop
(cd "$RS" && swift run rotoskop assemble "$RUNIX/src/rtest/testbcd1.s" -I "$RUNIX/src/include" -o /tmp/u-rs.bin)

# Golden
ca65 -t none -I "$RUNIX/src/include" -o /tmp/u.o "$RUNIX/src/rtest/testbcd1.s"
ld65 -C "$RUNIX/runix.cfg" -o /tmp/u-ca65.bin /tmp/u.o
cmp -l /tmp/u-rs.bin /tmp/u-ca65.bin | head
```

**Fix focus (assembler)**

1. **`&label` in macros** — `ldax &foo` / `bcd_load "…", &bcd_result` / `call …, &x` must take the `.match(.left(1,{arg}), &)` branch in `base.i` and emit `#</#>` + `cld` reloc marker as ca65 does.
2. **Nested macro expansion** — `bcd_load` body must fully expand `ldstr` and `call`; `call` must expand `mov`/`ldax` with substituted args (`ax`, `&dst`, `.paramcount`).
3. **Token funcs in conditions** — `.xmatch` / `.match` / `.left` / `.right` / `.tcount` on braced `{arg}` lists; verify against `ldax`/`mov`/`ld_a` in `base.i`.
4. **aoc*** — after (1–3), re-diff; suspect zp-vs-imm and unnamed-label / forward-ref interactions in dense `.byt` files. Prefer listing diffs (`--list`) over guessing.

---

## 2. Disk image vs Make golden

`rotoskop build` produces a valid **2IMG/RNIX** `.2mg` (same size as Make: 33553984 bytes; header matches).

**Full image is not byte-identical** to Make’s `build/runix.2mg` (~48k differing bytes starting in block 1 / root directory). Contributors:

- Assembler gaps above (wrong/short bins in demos/rtest change file payloads and block placement).
- Possible directory entry ordering / `next-free` differences once payloads differ.
- Packer should be re-validated against Make **after** assembler golden is green for all units (pack with identical `.bin` inputs → expect byte-identical `.2mg`).

**Target:** with identical bin inputs, `cmp` Make vs Rotoskop `.2mg` succeeds.

---

## 3. Runix `rotoskop` branch — leftover polish

Branch exists and builds (`rotoskop.yaml`, `font_to_asm.js`, `base_font.s` removed in favor of `build/generated/`). Still open vs design step 4:

- [ ] Wire **bootstub** + `run:` / `profiles:` so `rotoskop run` (or yaml-driven run) can boot the image like pim65 tests.
- [ ] Prove **byte-compare** on all bins + image once assembler gaps are closed.
- [ ] Decide whether Make remains co-installed on the branch until cutover (design: yes until merge to `main`).

---

## 4. Out of scope for the gap-fix pass

Do **not** start unless gaps above are closed (or explicitly requested):

- Step 5+ iOS app shell / Git / editor (§7, §1–3)
- libgit2, PAT UI, TextKit, etc.

---

## Suggested test plan when closing gaps

1. Unit-level: `testbcd1` then `testbcd2` size+bytes vs ca65.
2. Macro smoke: assemble a tiny file that only exercises `ldax &label`, `print "…"`, `call foo, &x`.
3. `aoc1a` / `aoc1b` byte compare.
4. Full `swift run rotoskop build` on runix `rotoskop` branch; `cmp` each `build/**/*.bin` to Make outputs; then `cmp` `.2mg`.
5. `swift test` in Rotoskop still green (57+ tests).
