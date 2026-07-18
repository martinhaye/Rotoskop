import Foundation
import Testing
@testable import RotoskopCore

@Suite("Integration")
struct IntegrationTests {
    func runProgram(_ code: [UInt8], start: UInt16 = 0x1000, maxInst: Int = 100) -> Simulator {
        let sim = Simulator(startAddress: start)
        sim.memory.loadBinary(code, at: start)
        sim.memory.setResetVector(start)
        sim.cpu.reset(clearIRQVectorTracking: false)
        _ = sim.run(maxInstructions: maxInst)
        return sim
    }

    @Test func simpleLoadStore() {
        let code: [UInt8] = [
            0xA9, 0x42,
            0x85, 0x10,
            0x4C, 0xF9, 0xFF,
        ]
        let sim = runProgram(code)
        #expect(sim.cpu.success)
        #expect(sim.memory.read(0x10) == 0x42)
    }

    @Test func countingLoop() {
        let code: [UInt8] = [
            0xA9, 0x00,
            0x18,
            0xC9, 0x05,
            0xF0, 0x05,
            0x69, 0x01,
            0x4C, 0x02, 0x10,
            0x85, 0x10,
            0x4C, 0xF9, 0xFF,
        ]
        let sim = runProgram(code)
        #expect(sim.cpu.success)
        #expect(sim.memory.read(0x10) == 0x05)
    }

    @Test func subroutineCall() {
        let code: [UInt8] = [
            0xA9, 0x10,
            0x18,
            0x20, 0x0D, 0x10,
            0x85, 0x20,
            0x4C, 0xF9, 0xFF,
            0x00, 0x00,
            0x69, 0x05,
            0x60,
        ]
        let sim = runProgram(code)
        #expect(sim.cpu.success)
        #expect(sim.memory.read(0x20) == 0x15)
    }

    @Test func memoryCopy() {
        let code: [UInt8] = [
            0xA9, 0x11, 0x85, 0x30,
            0xA9, 0x22, 0x85, 0x31,
            0xA9, 0x33, 0x85, 0x32,
            0xA9, 0x44, 0x85, 0x33,
            0xA2, 0x00,
            0xB5, 0x30,
            0x95, 0x40,
            0xE8,
            0xE0, 0x04,
            0xD0, 0xF7,
            0x4C, 0xF9, 0xFF,
        ]
        let sim = runProgram(code)
        #expect(sim.cpu.success)
        #expect(sim.memory.read(0x40) == 0x11)
        #expect(sim.memory.read(0x41) == 0x22)
        #expect(sim.memory.read(0x42) == 0x33)
        #expect(sim.memory.read(0x43) == 0x44)
    }

    @Test func keyboardSoftSwitches() {
        let sim = Simulator(startAddress: 0x1000)
        sim.setupKeyboard(inputStrings: ["Hi\\n"])
        let simple: [UInt8] = [
            0xAD, 0x00, 0xC0, // LDA $C000 → 'H'|0x80
            0x8D, 0x10, 0xC0, // clear strobe
            0x29, 0x7F,       // AND #$7F
            0x85, 0x10,
            0xAD, 0x00, 0xC0, // next key
            0x8D, 0x10, 0xC0,
            0x29, 0x7F,
            0x85, 0x11,
            0x4C, 0xF9, 0xFF,
        ]
        sim.memory.loadBinary(simple, at: 0x1000)
        sim.memory.setResetVector(0x1000)
        sim.cpu.reset(clearIRQVectorTracking: false)
        let reason = sim.run(maxInstructions: 100)
        #expect(reason == .success)
        #expect(sim.memory.read(0x10) == UInt8(ascii: "H"))
        #expect(sim.memory.read(0x11) == UInt8(ascii: "i"))
    }

    @Test func configJSONParse() throws {
        let dir = FileManager.default.temporaryDirectory
        let bin = dir.appendingPathComponent("t-\(UUID().uuidString).bin")
        let cfg = dir.appendingPathComponent("t-\(UUID().uuidString).json")
        try Data([0xA9, 0x01, 0x4C, 0xF9, 0xFF]).write(to: bin)
        let json = """
        {"binaries":[{"file":"\(bin.lastPathComponent)","load_addr":"0x1000"}],"start_addr":"$1000"}
        """
        try json.write(to: cfg, atomically: true, encoding: .utf8)
        defer {
            try? FileManager.default.removeItem(at: bin)
            try? FileManager.default.removeItem(at: cfg)
        }
        let parsed = try SimulatorConfig.fromJSONFile(cfg.path)
        #expect(parsed.startAddress == 0x1000)
        #expect(parsed.binaries.count == 1)
        #expect(parsed.binaries[0].loadAddress == 0x1000)
    }
}
