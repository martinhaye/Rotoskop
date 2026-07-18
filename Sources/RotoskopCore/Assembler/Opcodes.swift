/// 6502 official opcode table and addressing modes.
enum AddrMode: Equatable {
    case implied
    case accum
    case imm
    case zp
    case zpX
    case zpY
    case abs
    case absX
    case absY
    case indY      // (zp),Y
    case relative
    case ind       // (abs) JMP only — not used by runix but keep for completeness
}

struct OpcodeEntry {
    var mode: AddrMode
    var opcode: UInt8
    var size: Int  // total bytes including opcode
}

enum Opcodes {
    static let table: [String: [OpcodeEntry]] = {
        var t: [String: [OpcodeEntry]] = [:]
        func add(_ mnem: String, _ mode: AddrMode, _ op: UInt8, _ size: Int) {
            t[mnem, default: []].append(OpcodeEntry(mode: mode, opcode: op, size: size))
        }

        // ADC
        add("adc", .imm, 0x69, 2); add("adc", .zp, 0x65, 2); add("adc", .zpX, 0x75, 2)
        add("adc", .abs, 0x6D, 3); add("adc", .absX, 0x7D, 3); add("adc", .absY, 0x79, 3)
        add("adc", .indY, 0x71, 2)
        // AND
        add("and", .imm, 0x29, 2); add("and", .zp, 0x25, 2); add("and", .zpX, 0x35, 2)
        add("and", .abs, 0x2D, 3); add("and", .absX, 0x3D, 3); add("and", .absY, 0x39, 3)
        add("and", .indY, 0x31, 2)
        // ASL
        add("asl", .accum, 0x0A, 1); add("asl", .implied, 0x0A, 1)
        add("asl", .zp, 0x06, 2); add("asl", .zpX, 0x16, 2)
        add("asl", .abs, 0x0E, 3); add("asl", .absX, 0x1E, 3)
        // Branches
        for (m, op) in [("bcc",0x90),("bcs",0xB0),("beq",0xF0),("bmi",0x30),
                        ("bne",0xD0),("bpl",0x10),("bvc",0x50),("bvs",0x70)] {
            add(m, .relative, UInt8(op), 2)
        }
        // BIT
        add("bit", .zp, 0x24, 2); add("bit", .abs, 0x2C, 3)
        // BRK
        add("brk", .implied, 0x00, 1)
        add("brk", .imm, 0x00, 2) // ca65: `brk n` → $00, signature byte (no '#')
        // Flags / implied
        for (m, op) in [("clc",0x18),("cld",0xD8),("cli",0x58),("clv",0xB8),
                        ("sec",0x38),("sed",0xF8),("sei",0x78),
                        ("dex",0xCA),("dey",0x88),("inx",0xE8),("iny",0xC8),
                        ("nop",0xEA),("pha",0x48),("php",0x08),("pla",0x68),("plp",0x28),
                        ("rti",0x40),("rts",0x60),
                        ("tax",0xAA),("tay",0xA8),("tsx",0xBA),("txa",0x8A),("txs",0x9A),("tya",0x98)] {
            add(m, .implied, UInt8(op), 1)
        }
        // CMP
        add("cmp", .imm, 0xC9, 2); add("cmp", .zp, 0xC5, 2); add("cmp", .zpX, 0xD5, 2)
        add("cmp", .abs, 0xCD, 3); add("cmp", .absX, 0xDD, 3); add("cmp", .absY, 0xD9, 3)
        add("cmp", .indY, 0xD1, 2)
        // CPX / CPY
        add("cpx", .imm, 0xE0, 2); add("cpx", .zp, 0xE4, 2); add("cpx", .abs, 0xEC, 3)
        add("cpy", .imm, 0xC0, 2); add("cpy", .zp, 0xC4, 2); add("cpy", .abs, 0xCC, 3)
        // DEC / INC
        add("dec", .zp, 0xC6, 2); add("dec", .zpX, 0xD6, 2)
        add("dec", .abs, 0xCE, 3); add("dec", .absX, 0xDE, 3)
        add("inc", .zp, 0xE6, 2); add("inc", .zpX, 0xF6, 2)
        add("inc", .abs, 0xEE, 3); add("inc", .absX, 0xFE, 3)
        // EOR
        add("eor", .imm, 0x49, 2); add("eor", .zp, 0x45, 2); add("eor", .zpX, 0x55, 2)
        add("eor", .abs, 0x4D, 3); add("eor", .absX, 0x5D, 3); add("eor", .absY, 0x59, 3)
        add("eor", .indY, 0x51, 2)
        // JMP / JSR
        add("jmp", .abs, 0x4C, 3); add("jmp", .ind, 0x6C, 3)
        add("jsr", .abs, 0x20, 3)
        // LDA
        add("lda", .imm, 0xA9, 2); add("lda", .zp, 0xA5, 2); add("lda", .zpX, 0xB5, 2)
        add("lda", .abs, 0xAD, 3); add("lda", .absX, 0xBD, 3); add("lda", .absY, 0xB9, 3)
        add("lda", .indY, 0xB1, 2)
        // LDX
        add("ldx", .imm, 0xA2, 2); add("ldx", .zp, 0xA6, 2); add("ldx", .zpY, 0xB6, 2)
        add("ldx", .abs, 0xAE, 3); add("ldx", .absY, 0xBE, 3)
        // LDY
        add("ldy", .imm, 0xA0, 2); add("ldy", .zp, 0xA4, 2); add("ldy", .zpX, 0xB4, 2)
        add("ldy", .abs, 0xAC, 3); add("ldy", .absX, 0xBC, 3)
        // LSR
        add("lsr", .accum, 0x4A, 1); add("lsr", .implied, 0x4A, 1)
        add("lsr", .zp, 0x46, 2); add("lsr", .zpX, 0x56, 2)
        add("lsr", .abs, 0x4E, 3); add("lsr", .absX, 0x5E, 3)
        // ORA
        add("ora", .imm, 0x09, 2); add("ora", .zp, 0x05, 2); add("ora", .zpX, 0x15, 2)
        add("ora", .abs, 0x0D, 3); add("ora", .absX, 0x1D, 3); add("ora", .absY, 0x19, 3)
        add("ora", .indY, 0x11, 2)
        // ROL / ROR
        add("rol", .accum, 0x2A, 1); add("rol", .implied, 0x2A, 1)
        add("rol", .zp, 0x26, 2); add("rol", .zpX, 0x36, 2)
        add("rol", .abs, 0x2E, 3); add("rol", .absX, 0x3E, 3)
        add("ror", .accum, 0x6A, 1); add("ror", .implied, 0x6A, 1)
        add("ror", .zp, 0x66, 2); add("ror", .zpX, 0x76, 2)
        add("ror", .abs, 0x6E, 3); add("ror", .absX, 0x7E, 3)
        // SBC
        add("sbc", .imm, 0xE9, 2); add("sbc", .zp, 0xE5, 2); add("sbc", .zpX, 0xF5, 2)
        add("sbc", .abs, 0xED, 3); add("sbc", .absX, 0xFD, 3); add("sbc", .absY, 0xF9, 3)
        add("sbc", .indY, 0xF1, 2)
        // STA
        add("sta", .zp, 0x85, 2); add("sta", .zpX, 0x95, 2)
        add("sta", .abs, 0x8D, 3); add("sta", .absX, 0x9D, 3); add("sta", .absY, 0x99, 3)
        add("sta", .indY, 0x91, 2)
        // STX / STY
        add("stx", .zp, 0x86, 2); add("stx", .zpY, 0x96, 2); add("stx", .abs, 0x8E, 3)
        add("sty", .zp, 0x84, 2); add("sty", .zpX, 0x94, 2); add("sty", .abs, 0x8C, 3)

        return t
    }()

    static func lookup(_ mnemonic: String) -> [OpcodeEntry]? {
        table[mnemonic.lowercased()]
    }
}
