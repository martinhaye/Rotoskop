import XCTest
@testable import RotoskopEmulator

final class MachineTests: XCTestCase {

    func testRunUntilBRK() {
        let machine = Machine()
        // LDA #$05 ; TAX ; INX ; BRK
        machine.load([0xA9, 0x05, 0xAA, 0xE8, 0x00])
        let reason = machine.run()
        XCTAssertEqual(reason, .halted)
        XCTAssertEqual(machine.cpu.a, 0x05)
        XCTAssertEqual(machine.cpu.x, 0x06)
    }

    func testBreakpointStopsExecution() {
        let machine = Machine()
        // 0800: LDA #$01 ; 0802: LDA #$02 ; 0804: BRK
        machine.load([0xA9, 0x01, 0xA9, 0x02, 0x00])
        machine.breakpoints = [0x0802]
        let reason = machine.run()
        XCTAssertEqual(reason, .breakpoint(0x0802))
        XCTAssertEqual(machine.cpu.a, 0x01) // second LDA not yet executed
    }

    func testWriteToTextScreenIsDecodable() {
        let machine = Machine()
        // Write 'H','I' to the start of the text screen ($0400).
        // LDA #$C8 ('H'|0x80) ; STA $0400 ; LDA #$C9 ('I'|0x80) ; STA $0401 ; BRK
        machine.load([0xA9, 0xC8, 0x8D, 0x00, 0x04,
                      0xA9, 0xC9, 0x8D, 0x01, 0x04, 0x00])
        machine.run()
        let firstRow = machine.screenLines()[0]
        XCTAssertTrue(firstRow.hasPrefix("HI"), "row was: \(firstRow)")
    }

    func testTextScreenRowInterleaving() {
        let screen = TextScreen()
        XCTAssertEqual(screen.rowAddress(0), 0x0400)
        XCTAssertEqual(screen.rowAddress(1), 0x0480)
        XCTAssertEqual(screen.rowAddress(8), 0x0428)
        XCTAssertEqual(screen.rowAddress(16), 0x0450)
    }

    func testDisassembler() {
        let ram = RAM()
        ram.load([0xA9, 0x41, 0x8D, 0x00, 0x04], at: 0x0800)
        let disasm = Disassembler()
        let lines = disasm.disassemble(from: 0x0800, count: 2, bus: ram)
        XCTAssertEqual(lines[0].mnemonic, "LDA")
        XCTAssertEqual(lines[0].operandText, "#$41")
        XCTAssertEqual(lines[1].mnemonic, "STA")
        XCTAssertEqual(lines[1].operandText, "$0400")
    }
}
