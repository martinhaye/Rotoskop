/// Base cycle counts for official NMOS 6502 opcodes (no page-cross penalties).
/// Branch opcodes store the not-taken cost (2); `CPU` adds +1 when the branch is taken.
enum OpcodeCycles {
    /// Indexed by opcode; `0` means unused / illegal in our table.
    static let base: [UInt8] = {
        var c = [UInt8](repeating: 0, count: 256)

        // ADC / AND / EOR / ORA / SBC / CMP (read)
        for op in [0x69, 0x29, 0x49, 0x09, 0xE9, 0xC9] as [UInt8] { c[Int(op)] = 2 } // #
        for op in [0x65, 0x25, 0x45, 0x05, 0xE5, 0xC5] as [UInt8] { c[Int(op)] = 3 } // zp
        for op in [0x75, 0x35, 0x55, 0x15, 0xF5, 0xD5] as [UInt8] { c[Int(op)] = 4 } // zp,x
        for op in [0x6D, 0x2D, 0x4D, 0x0D, 0xED, 0xCD] as [UInt8] { c[Int(op)] = 4 } // abs
        for op in [0x7D, 0x3D, 0x5D, 0x1D, 0xFD, 0xDD] as [UInt8] { c[Int(op)] = 4 } // abs,x
        for op in [0x79, 0x39, 0x59, 0x19, 0xF9, 0xD9] as [UInt8] { c[Int(op)] = 4 } // abs,y
        for op in [0x61, 0x21, 0x41, 0x01, 0xE1, 0xC1] as [UInt8] { c[Int(op)] = 6 } // (zp,x)
        for op in [0x71, 0x31, 0x51, 0x11, 0xF1, 0xD1] as [UInt8] { c[Int(op)] = 5 } // (zp),y

        // ASL / LSR / ROL / ROR
        for op in [0x0A, 0x4A, 0x2A, 0x6A] as [UInt8] { c[Int(op)] = 2 } // A
        for op in [0x06, 0x46, 0x26, 0x66] as [UInt8] { c[Int(op)] = 5 } // zp
        for op in [0x16, 0x56, 0x36, 0x76] as [UInt8] { c[Int(op)] = 6 } // zp,x
        for op in [0x0E, 0x4E, 0x2E, 0x6E] as [UInt8] { c[Int(op)] = 6 } // abs
        for op in [0x1E, 0x5E, 0x3E, 0x7E] as [UInt8] { c[Int(op)] = 7 } // abs,x

        // Branches (not-taken); +1 when taken applied in CPU
        for op in [0x90, 0xB0, 0xF0, 0x30, 0xD0, 0x10, 0x50, 0x70] as [UInt8] {
            c[Int(op)] = 2
        }

        c[0x24] = 3; c[0x2C] = 4 // BIT
        c[0x00] = 7 // BRK

        // Flag ops
        for op in [0x18, 0xD8, 0x58, 0xB8, 0x38, 0xF8, 0x78] as [UInt8] { c[Int(op)] = 2 }

        // CPX / CPY
        c[0xE0] = 2; c[0xE4] = 3; c[0xEC] = 4
        c[0xC0] = 2; c[0xC4] = 3; c[0xCC] = 4

        // DEC / INC mem
        c[0xC6] = 5; c[0xD6] = 6; c[0xCE] = 6; c[0xDE] = 7
        c[0xE6] = 5; c[0xF6] = 6; c[0xEE] = 6; c[0xFE] = 7
        c[0xCA] = 2; c[0x88] = 2 // DEX / DEY
        c[0xE8] = 2; c[0xC8] = 2 // INX / INY

        c[0x4C] = 3; c[0x6C] = 5 // JMP
        c[0x20] = 6 // JSR

        // LDA
        c[0xA9] = 2; c[0xA5] = 3; c[0xB5] = 4; c[0xAD] = 4
        c[0xBD] = 4; c[0xB9] = 4; c[0xA1] = 6; c[0xB1] = 5
        // LDX
        c[0xA2] = 2; c[0xA6] = 3; c[0xB6] = 4; c[0xAE] = 4; c[0xBE] = 4
        // LDY
        c[0xA0] = 2; c[0xA4] = 3; c[0xB4] = 4; c[0xAC] = 4; c[0xBC] = 4

        c[0xEA] = 2 // NOP

        c[0x48] = 3; c[0x08] = 3; c[0x68] = 4; c[0x28] = 4 // PHA/PHP/PLA/PLP
        c[0x40] = 6; c[0x60] = 6 // RTI / RTS

        // STA (writes: abs,x/y and (zp),y are 5/6 without page-cross nuance)
        c[0x85] = 3; c[0x95] = 4; c[0x8D] = 4; c[0x9D] = 5; c[0x99] = 5
        c[0x81] = 6; c[0x91] = 6
        c[0x86] = 3; c[0x96] = 4; c[0x8E] = 4 // STX
        c[0x84] = 3; c[0x94] = 4; c[0x8C] = 4 // STY

        for op in [0xAA, 0xA8, 0xBA, 0x8A, 0x9A, 0x98] as [UInt8] { c[Int(op)] = 2 }

        return c
    }()

    /// Nominal cycle charge for PC hooks (e.g. HD intercept) — not a real 6502 op.
    static let pcHookCycles: Int = 6
}
