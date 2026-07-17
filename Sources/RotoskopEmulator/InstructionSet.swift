//
//  InstructionSet.swift
//  RotoskopEmulator
//
//  The opcode dispatch table. This is the primary seam for porting the existing
//  Python core: each entry maps an opcode byte to a mnemonic, an addressing
//  mode, a cycle count, and a handler built from the helpers in
//  `Instructions.swift`.
//
//  STATUS: this table currently implements a representative slice of the
//  official NMOS 6502 set — every instruction *family* is present so the
//  addressing/flag/cycle machinery is exercised end to end, but not every
//  opcode/mode combination is filled in yet. Completing it (and the unofficial
//  opcodes, if we want them) is the next step once the Python core is on hand.
//

/// A single decoded instruction: metadata plus its behaviour.
struct Instruction {
    let mnemonic: String
    let mode: AddressingMode
    let baseCycles: Int
    let addsCycleOnPageCross: Bool
    let execute: (CPU6502, Operand) -> Void
}

enum InstructionSet {

    /// Builds the 256-entry opcode table. Unimplemented opcodes are `nil` and
    /// cause the CPU to halt (so gaps surface loudly in tests rather than
    /// silently misbehaving).
    static func buildTable() -> [Instruction?] {
        var t = [Instruction?](repeating: nil, count: 256)

        func set(_ opcode: UInt8,
                 _ mnemonic: String,
                 _ mode: AddressingMode,
                 _ cycles: Int,
                 pageCross: Bool = false,
                 _ execute: @escaping (CPU6502, Operand) -> Void) {
            t[Int(opcode)] = Instruction(mnemonic: mnemonic,
                                         mode: mode,
                                         baseCycles: cycles,
                                         addsCycleOnPageCross: pageCross,
                                         execute: execute)
        }

        // MARK: LDA
        set(0xA9, "LDA", .immediate, 2)        { c, o in c.loadA(o) }
        set(0xA5, "LDA", .zeroPage, 3)         { c, o in c.loadA(o) }
        set(0xB5, "LDA", .zeroPageX, 4)        { c, o in c.loadA(o) }
        set(0xAD, "LDA", .absolute, 4)         { c, o in c.loadA(o) }
        set(0xBD, "LDA", .absoluteX, 4, pageCross: true) { c, o in c.loadA(o) }
        set(0xB9, "LDA", .absoluteY, 4, pageCross: true) { c, o in c.loadA(o) }
        set(0xA1, "LDA", .indexedIndirect, 6)  { c, o in c.loadA(o) }
        set(0xB1, "LDA", .indirectIndexed, 5, pageCross: true) { c, o in c.loadA(o) }

        // MARK: LDX
        set(0xA2, "LDX", .immediate, 2)        { c, o in c.loadX(o) }
        set(0xA6, "LDX", .zeroPage, 3)         { c, o in c.loadX(o) }
        set(0xB6, "LDX", .zeroPageY, 4)        { c, o in c.loadX(o) }
        set(0xAE, "LDX", .absolute, 4)         { c, o in c.loadX(o) }
        set(0xBE, "LDX", .absoluteY, 4, pageCross: true) { c, o in c.loadX(o) }

        // MARK: LDY
        set(0xA0, "LDY", .immediate, 2)        { c, o in c.loadY(o) }
        set(0xA4, "LDY", .zeroPage, 3)         { c, o in c.loadY(o) }
        set(0xB4, "LDY", .zeroPageX, 4)        { c, o in c.loadY(o) }
        set(0xAC, "LDY", .absolute, 4)         { c, o in c.loadY(o) }
        set(0xBC, "LDY", .absoluteX, 4, pageCross: true) { c, o in c.loadY(o) }

        // MARK: STA
        set(0x85, "STA", .zeroPage, 3)         { c, o in c.store(c.a, o) }
        set(0x95, "STA", .zeroPageX, 4)        { c, o in c.store(c.a, o) }
        set(0x8D, "STA", .absolute, 4)         { c, o in c.store(c.a, o) }
        set(0x9D, "STA", .absoluteX, 5)        { c, o in c.store(c.a, o) }
        set(0x99, "STA", .absoluteY, 5)        { c, o in c.store(c.a, o) }
        set(0x81, "STA", .indexedIndirect, 6)  { c, o in c.store(c.a, o) }
        set(0x91, "STA", .indirectIndexed, 6)  { c, o in c.store(c.a, o) }

        // MARK: STX / STY
        set(0x86, "STX", .zeroPage, 3)         { c, o in c.store(c.x, o) }
        set(0x96, "STX", .zeroPageY, 4)        { c, o in c.store(c.x, o) }
        set(0x8E, "STX", .absolute, 4)         { c, o in c.store(c.x, o) }
        set(0x84, "STY", .zeroPage, 3)         { c, o in c.store(c.y, o) }
        set(0x94, "STY", .zeroPageX, 4)        { c, o in c.store(c.y, o) }
        set(0x8C, "STY", .absolute, 4)         { c, o in c.store(c.y, o) }

        // MARK: Register transfers
        set(0xAA, "TAX", .implied, 2) { c, _ in c.x = c.transfer(c.a) }
        set(0xA8, "TAY", .implied, 2) { c, _ in c.y = c.transfer(c.a) }
        set(0x8A, "TXA", .implied, 2) { c, _ in c.a = c.transfer(c.x) }
        set(0x98, "TYA", .implied, 2) { c, _ in c.a = c.transfer(c.y) }
        set(0xBA, "TSX", .implied, 2) { c, _ in c.x = c.transfer(c.sp) }
        set(0x9A, "TXS", .implied, 2) { c, _ in c.sp = c.transfer(c.x, updatingFlags: false) }

        // MARK: Increment / decrement
        set(0xE8, "INX", .implied, 2) { c, _ in c.x = c.x &+ 1; c.p.updateZeroNegative(c.x) }
        set(0xC8, "INY", .implied, 2) { c, _ in c.y = c.y &+ 1; c.p.updateZeroNegative(c.y) }
        set(0xCA, "DEX", .implied, 2) { c, _ in c.x = c.x &- 1; c.p.updateZeroNegative(c.x) }
        set(0x88, "DEY", .implied, 2) { c, _ in c.y = c.y &- 1; c.p.updateZeroNegative(c.y) }
        set(0xE6, "INC", .zeroPage, 5)  { c, o in c.increment(memory: o) }
        set(0xF6, "INC", .zeroPageX, 6) { c, o in c.increment(memory: o) }
        set(0xEE, "INC", .absolute, 6)  { c, o in c.increment(memory: o) }
        set(0xFE, "INC", .absoluteX, 7) { c, o in c.increment(memory: o) }
        set(0xC6, "DEC", .zeroPage, 5)  { c, o in c.decrement(memory: o) }
        set(0xD6, "DEC", .zeroPageX, 6) { c, o in c.decrement(memory: o) }
        set(0xCE, "DEC", .absolute, 6)  { c, o in c.decrement(memory: o) }
        set(0xDE, "DEC", .absoluteX, 7) { c, o in c.decrement(memory: o) }

        // MARK: Arithmetic (ADC / SBC)
        for (opcode, mode, cycles, cross) in [
            (UInt8(0x69), AddressingMode.immediate, 2, false),
            (0x65, .zeroPage, 3, false), (0x75, .zeroPageX, 4, false),
            (0x6D, .absolute, 4, false), (0x7D, .absoluteX, 4, true),
            (0x79, .absoluteY, 4, true), (0x61, .indexedIndirect, 6, false),
            (0x71, .indirectIndexed, 5, true),
        ] { set(opcode, "ADC", mode, cycles, pageCross: cross) { c, o in c.adc(o) } }

        for (opcode, mode, cycles, cross) in [
            (UInt8(0xE9), AddressingMode.immediate, 2, false),
            (0xE5, .zeroPage, 3, false), (0xF5, .zeroPageX, 4, false),
            (0xED, .absolute, 4, false), (0xFD, .absoluteX, 4, true),
            (0xF9, .absoluteY, 4, true), (0xE1, .indexedIndirect, 6, false),
            (0xF1, .indirectIndexed, 5, true),
        ] { set(opcode, "SBC", mode, cycles, pageCross: cross) { c, o in c.sbc(o) } }

        // MARK: Logic (AND / ORA / EOR)
        for (opcode, mode, cycles, cross) in [
            (UInt8(0x29), AddressingMode.immediate, 2, false),
            (0x25, .zeroPage, 3, false), (0x35, .zeroPageX, 4, false),
            (0x2D, .absolute, 4, false), (0x3D, .absoluteX, 4, true),
            (0x39, .absoluteY, 4, true), (0x21, .indexedIndirect, 6, false),
            (0x31, .indirectIndexed, 5, true),
        ] { set(opcode, "AND", mode, cycles, pageCross: cross) { c, o in c.and(o) } }

        for (opcode, mode, cycles, cross) in [
            (UInt8(0x09), AddressingMode.immediate, 2, false),
            (0x05, .zeroPage, 3, false), (0x15, .zeroPageX, 4, false),
            (0x0D, .absolute, 4, false), (0x1D, .absoluteX, 4, true),
            (0x19, .absoluteY, 4, true), (0x01, .indexedIndirect, 6, false),
            (0x11, .indirectIndexed, 5, true),
        ] { set(opcode, "ORA", mode, cycles, pageCross: cross) { c, o in c.ora(o) } }

        for (opcode, mode, cycles, cross) in [
            (UInt8(0x49), AddressingMode.immediate, 2, false),
            (0x45, .zeroPage, 3, false), (0x55, .zeroPageX, 4, false),
            (0x4D, .absolute, 4, false), (0x5D, .absoluteX, 4, true),
            (0x59, .absoluteY, 4, true), (0x41, .indexedIndirect, 6, false),
            (0x51, .indirectIndexed, 5, true),
        ] { set(opcode, "EOR", mode, cycles, pageCross: cross) { c, o in c.eor(o) } }

        // MARK: BIT
        set(0x24, "BIT", .zeroPage, 3) { c, o in c.bit(o) }
        set(0x2C, "BIT", .absolute, 4) { c, o in c.bit(o) }

        // MARK: Compares
        for (opcode, mode, cycles, cross) in [
            (UInt8(0xC9), AddressingMode.immediate, 2, false),
            (0xC5, .zeroPage, 3, false), (0xD5, .zeroPageX, 4, false),
            (0xCD, .absolute, 4, false), (0xDD, .absoluteX, 4, true),
            (0xD9, .absoluteY, 4, true), (0xC1, .indexedIndirect, 6, false),
            (0xD1, .indirectIndexed, 5, true),
        ] { set(opcode, "CMP", mode, cycles, pageCross: cross) { c, o in c.compare(c.a, o) } }

        set(0xE0, "CPX", .immediate, 2) { c, o in c.compare(c.x, o) }
        set(0xE4, "CPX", .zeroPage, 3)  { c, o in c.compare(c.x, o) }
        set(0xEC, "CPX", .absolute, 4)  { c, o in c.compare(c.x, o) }
        set(0xC0, "CPY", .immediate, 2) { c, o in c.compare(c.y, o) }
        set(0xC4, "CPY", .zeroPage, 3)  { c, o in c.compare(c.y, o) }
        set(0xCC, "CPY", .absolute, 4)  { c, o in c.compare(c.y, o) }

        // MARK: Shifts / rotates
        let asl: (UInt8, Bool) -> (UInt8, Bool) = { v, _ in (v << 1, v & 0x80 != 0) }
        let lsr: (UInt8, Bool) -> (UInt8, Bool) = { v, _ in (v >> 1, v & 0x01 != 0) }
        let rol: (UInt8, Bool) -> (UInt8, Bool) = { v, cin in ((v << 1) | (cin ? 1 : 0), v & 0x80 != 0) }
        let ror: (UInt8, Bool) -> (UInt8, Bool) = { v, cin in ((v >> 1) | (cin ? 0x80 : 0), v & 0x01 != 0) }
        for (mnemonic, op, entries) in [
            ("ASL", asl, [(UInt8(0x0A), AddressingMode.accumulator, 2),
                          (0x06, .zeroPage, 5), (0x16, .zeroPageX, 6),
                          (0x0E, .absolute, 6), (0x1E, .absoluteX, 7)]),
            ("LSR", lsr, [(0x4A, .accumulator, 2),
                          (0x46, .zeroPage, 5), (0x56, .zeroPageX, 6),
                          (0x4E, .absolute, 6), (0x5E, .absoluteX, 7)]),
            ("ROL", rol, [(0x2A, .accumulator, 2),
                          (0x26, .zeroPage, 5), (0x36, .zeroPageX, 6),
                          (0x2E, .absolute, 6), (0x3E, .absoluteX, 7)]),
            ("ROR", ror, [(0x6A, .accumulator, 2),
                          (0x66, .zeroPage, 5), (0x76, .zeroPageX, 6),
                          (0x6E, .absolute, 6), (0x7E, .absoluteX, 7)]),
        ] {
            for (opcode, mode, cycles) in entries {
                set(opcode, mnemonic, mode, cycles) { c, o in c.shift(o, op) }
            }
        }

        // MARK: Flag operations
        set(0x18, "CLC", .implied, 2) { c, _ in c.p.remove(.carry) }
        set(0x38, "SEC", .implied, 2) { c, _ in c.p.insert(.carry) }
        set(0x58, "CLI", .implied, 2) { c, _ in c.p.remove(.interrupt) }
        set(0x78, "SEI", .implied, 2) { c, _ in c.p.insert(.interrupt) }
        set(0xB8, "CLV", .implied, 2) { c, _ in c.p.remove(.overflow) }
        set(0xD8, "CLD", .implied, 2) { c, _ in c.p.remove(.decimal) }
        set(0xF8, "SED", .implied, 2) { c, _ in c.p.insert(.decimal) }

        // MARK: Branches
        set(0x10, "BPL", .relative, 2, pageCross: true) { c, o in c.branch(!c.p.contains(.negative), o) }
        set(0x30, "BMI", .relative, 2, pageCross: true) { c, o in c.branch(c.p.contains(.negative), o) }
        set(0x50, "BVC", .relative, 2, pageCross: true) { c, o in c.branch(!c.p.contains(.overflow), o) }
        set(0x70, "BVS", .relative, 2, pageCross: true) { c, o in c.branch(c.p.contains(.overflow), o) }
        set(0x90, "BCC", .relative, 2, pageCross: true) { c, o in c.branch(!c.p.contains(.carry), o) }
        set(0xB0, "BCS", .relative, 2, pageCross: true) { c, o in c.branch(c.p.contains(.carry), o) }
        set(0xD0, "BNE", .relative, 2, pageCross: true) { c, o in c.branch(!c.p.contains(.zero), o) }
        set(0xF0, "BEQ", .relative, 2, pageCross: true) { c, o in c.branch(c.p.contains(.zero), o) }

        // MARK: Jumps / subroutines
        set(0x4C, "JMP", .absolute, 3) { c, o in if let a = c.effectiveAddress(o) { c.pc = a } }
        set(0x6C, "JMP", .indirect, 5) { c, o in if let a = c.effectiveAddress(o) { c.pc = a } }
        set(0x20, "JSR", .absolute, 6) { c, o in c.jsr(o) }
        set(0x60, "RTS", .implied, 6)  { c, _ in c.rts() }
        set(0x40, "RTI", .implied, 6)  { c, _ in c.rti() }

        // MARK: Stack
        set(0x48, "PHA", .implied, 3) { c, _ in c.pha() }
        set(0x68, "PLA", .implied, 4) { c, _ in c.pla() }
        set(0x08, "PHP", .implied, 3) { c, _ in c.php() }
        set(0x28, "PLP", .implied, 4) { c, _ in c.plp() }

        // MARK: Misc
        set(0xEA, "NOP", .implied, 2) { _, _ in }
        set(0x00, "BRK", .implied, 7) { c, _ in c.brk() }

        return t
    }
}
