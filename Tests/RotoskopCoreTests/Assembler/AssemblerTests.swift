import Foundation
import Testing
@testable import RotoskopCore

@Suite("Assembler basics")
struct AssemblerBasicTests {
    @Test func haltLike() {
        let src = """
        .org $1000
        jmp $FFF9
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "halt.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.baseAddress == 0x1000)
        #expect(r.binary == [0x4C, 0xF9, 0xFF])
    }

    @Test func equatesAndZp() {
        let src = """
        tmp = $6
        .org $2000
        lda #$42
        sta tmp
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xA9, 0x42, 0x85, 0x06])
    }

    @Test func labelsAndBranch() {
        let src = """
        .org $1000
        ldx #5
        loop:
        dex
        bne loop
        jmp $FFF9
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        // LDX #5; DEX; BNE -3; JMP $FFF9
        #expect(r.binary[0] == 0xA2)
        #expect(r.binary[1] == 0x05)
        #expect(r.binary[2] == 0xCA) // DEX
        #expect(r.binary[3] == 0xD0) // BNE
        #expect(r.binary[4] == 0xFD) // -3
    }

    @Test func bytString() {
        let src = """
        .org $2000
        .byt 1,"Hi"
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded)
        #expect(r.binary == [0x01, 0x48, 0x69])
    }

    @Test func indirectY() {
        let src = """
        ptmp = $8
        .org $1000
        lda (ptmp),y
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xB1, 0x08])
    }

    @Test func unnamedLabels() {
        let src = """
        .org $1000
        bcc :+
        nop
        :
        jmp $FFF9
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary[0] == 0x90) // BCC
        #expect(r.binary[1] == 0x01) // +1 over NOP to :
    }
}

@Suite("Assembler macros")
struct AssemblerMacroTests {
    @Test func simpleMacro() {
        let src = """
        .macro poke addr, val
        lda #val
        sta addr
        .endmacro
        .org $1000
        poke $10, $42
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xA9, 0x42, 0x85, 0x10])
    }

    @Test func strlenInByte() {
        let src = """
        .feature string_escapes
        .org $1000
        .byte .strlen("Hi"), "Hi"
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0x02, 0x48, 0x69])
    }

    @Test func matchXmatch() {
        let src = """
        .macro pick arg
        .if (.xmatch ({arg}, {a}))
        tax
        .else
        lda arg
        .endif
        .endmacro
        .org $1000
        pick a
        pick $10
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xAA, 0xA5, 0x10]) // TAX; LDA $10
    }

    @Test func paramcountComparisons() {
        // Mirrors runix call macro: .paramcount >= / = must select the right branch.
        let src = """
        .macro call func, arg0, arg1, arg2
        .if .paramcount >= 5
        nop
        .elseif .paramcount = 4
        lda #4
        .elseif .paramcount = 3
        lda #3
        .elseif .paramcount = 2
        lda #2
        .else
        lda #0
        .endif
        jsr func
        .endmacro
        .org $1000
        call $C60, ax, &$2000
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xA9, 0x03, 0x20, 0x60, 0x0C])
    }

    @Test func ldaxAmpAddress() {
        let src = """
        .macro ldax arg
        .if (.xmatch ({arg}, {ax}))
        nop
        .elseif (.match (.left(1, {arg}), #))
        lda #<(.right(.tcount({arg})-1, {arg}))
        ldx #>(.right(.tcount({arg})-1, {arg}))
        .elseif (.match (.left(1, {arg}), &))
        lda #<(.right(.tcount({arg})-1, {arg}))
        cld
        ldx #>(.right(.tcount({arg})-1, {arg}))
        .else
        lda arg
        ldx 1+(arg)
        .endif
        .endmacro
        .org $1000
        ldax &$1234
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0xA9, 0x34, 0xD8, 0xA2, 0x12])
    }

    @Test func brkWithSignature() {
        let src = """
        .org $1000
        brk
        brk 0
        brk $42
        """
        let asm = Assembler(options: AssembleOptions(generateListing: false))
        let r = asm.assemble(source: src, file: "t.s")
        #expect(r.succeeded, "diags: \(r.diagnostics)")
        #expect(r.binary == [0x00, 0x00, 0x00, 0x00, 0x42])
    }
}
