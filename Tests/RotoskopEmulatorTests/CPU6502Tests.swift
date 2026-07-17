import XCTest
@testable import RotoskopEmulator

final class CPU6502Tests: XCTestCase {

    private func makeCPU() -> (CPU6502, RAM) {
        let ram = RAM()
        let cpu = CPU6502(bus: ram)
        cpu.pc = 0x0800
        return (cpu, ram)
    }

    func testLDAImmediateSetsAccumulatorAndFlags() {
        let (cpu, ram) = makeCPU()
        ram.load([0xA9, 0x42], at: 0x0800)   // LDA #$42
        cpu.step()
        XCTAssertEqual(cpu.a, 0x42)
        XCTAssertFalse(cpu.p.contains(.zero))
        XCTAssertFalse(cpu.p.contains(.negative))
        XCTAssertEqual(cpu.cycles, 2)
    }

    func testLDAImmediateZeroSetsZeroFlag() {
        let (cpu, ram) = makeCPU()
        ram.load([0xA9, 0x00], at: 0x0800)
        cpu.step()
        XCTAssertTrue(cpu.p.contains(.zero))
    }

    func testLDAImmediateNegativeSetsNegativeFlag() {
        let (cpu, ram) = makeCPU()
        ram.load([0xA9, 0x80], at: 0x0800)
        cpu.step()
        XCTAssertTrue(cpu.p.contains(.negative))
    }

    func testStoreAndLoadRoundTrip() {
        let (cpu, ram) = makeCPU()
        // LDA #$AB ; STA $10 ; LDA #$00 ; LDA $10
        ram.load([0xA9, 0xAB, 0x85, 0x10, 0xA9, 0x00, 0xA5, 0x10], at: 0x0800)
        for _ in 0..<4 { cpu.step() }
        XCTAssertEqual(cpu.a, 0xAB)
        XCTAssertEqual(ram.read(0x10), 0xAB)
    }

    func testADCWithCarryAndOverflow() {
        let (cpu, ram) = makeCPU()
        // CLC ; LDA #$50 ; ADC #$50  => $A0, overflow set, negative set
        ram.load([0x18, 0xA9, 0x50, 0x69, 0x50], at: 0x0800)
        for _ in 0..<3 { cpu.step() }
        XCTAssertEqual(cpu.a, 0xA0)
        XCTAssertTrue(cpu.p.contains(.overflow))
        XCTAssertTrue(cpu.p.contains(.negative))
        XCTAssertFalse(cpu.p.contains(.carry))
    }

    func testSBCSubtracts() {
        let (cpu, ram) = makeCPU()
        // SEC ; LDA #$50 ; SBC #$30 => $20
        ram.load([0x38, 0xA9, 0x50, 0xE9, 0x30], at: 0x0800)
        for _ in 0..<3 { cpu.step() }
        XCTAssertEqual(cpu.a, 0x20)
        XCTAssertTrue(cpu.p.contains(.carry)) // no borrow
    }

    func testINXWrapsAndSetsZero() {
        let (cpu, ram) = makeCPU()
        // LDX #$FF ; INX
        ram.load([0xA2, 0xFF, 0xE8], at: 0x0800)
        cpu.step(); cpu.step()
        XCTAssertEqual(cpu.x, 0x00)
        XCTAssertTrue(cpu.p.contains(.zero))
    }

    func testBranchTakenAndNotTaken() {
        let (cpu, ram) = makeCPU()
        // LDA #$00 (Z=1) ; BEQ +2 ; LDA #$FF ; (target) LDA #$11
        ram.load([0xA9, 0x00, 0xF0, 0x02, 0xA9, 0xFF, 0xA9, 0x11], at: 0x0800)
        cpu.step() // LDA #$00
        cpu.step() // BEQ taken -> skips LDA #$FF
        cpu.step() // LDA #$11
        XCTAssertEqual(cpu.a, 0x11)
    }

    func testJSRandRTS() {
        let (cpu, ram) = makeCPU()
        // 0800: JSR $0806 ; 0803: LDA #$99 ; 0805: BRK
        // 0806: LDA #$01 ; 0808: RTS
        ram.load([0x20, 0x06, 0x08, 0xA9, 0x99, 0x00], at: 0x0800)
        ram.load([0xA9, 0x01, 0x60], at: 0x0806)
        cpu.step() // JSR
        XCTAssertEqual(cpu.pc, 0x0806)
        cpu.step() // LDA #$01
        cpu.step() // RTS
        XCTAssertEqual(cpu.pc, 0x0803)
        cpu.step() // LDA #$99
        XCTAssertEqual(cpu.a, 0x99)
    }

    func testUnimplementedOpcodeHalts() {
        let (cpu, ram) = makeCPU()
        ram.load([0xFF], at: 0x0800)  // not implemented
        cpu.step()
        XCTAssertTrue(cpu.halted)
    }
}
