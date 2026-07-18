import Testing
@testable import RotoskopCore

@Suite("Memory")
struct MemoryTests {
    @Test func initialState() {
        let mem = Memory()
        #expect(mem.read(0x0000) == 0xFF)
        #expect(mem.read(0x1234) == 0xFF)
        #expect(mem.read(0xFFFF) == 0xFF)
    }

    @Test func readWriteByte() {
        let mem = Memory()
        mem.write(0x1000, 0x42)
        #expect(mem.read(0x1000) == 0x42)
    }

    @Test func addressWraps() {
        let mem = Memory()
        // UInt16 naturally wraps; writing via truncated address
        mem.write(0x0000, 0x42)
        #expect(mem.read(0x0000) == 0x42)
    }

    @Test func readWriteWord() {
        let mem = Memory()
        mem.write(0x1000, 0x34)
        mem.write(0x1001, 0x12)
        #expect(mem.readWord(0x1000) == 0x1234)
        mem.writeWord(0x2000, 0xABCD)
        #expect(mem.read(0x2000) == 0xCD)
        #expect(mem.read(0x2001) == 0xAB)
    }

    @Test func readWordWraps() {
        let mem = Memory()
        mem.write(0xFFFF, 0x34)
        mem.write(0x0000, 0x12)
        #expect(mem.readWord(0xFFFF) == 0x1234)
    }

    @Test func readWordZP() {
        let mem = Memory()
        mem.write(0xFF, 0x34)
        mem.write(0x00, 0x12)
        #expect(mem.readWordZP(0xFF) == 0x1234)
    }

    @Test func loadBinaryAndResetVector() {
        let mem = Memory()
        mem.loadBinary([0x01, 0x02, 0x03, 0x04], at: 0x1000)
        #expect(mem.read(0x1000) == 0x01)
        #expect(mem.read(0x1003) == 0x04)
        mem.setResetVector(0x0800)
        #expect(mem.readWord(0xFFFC) == 0x0800)
    }

    @Test func dumpBypassesHooks() {
        let mem = Memory()
        mem.write(0x1000, 0xAA)
        var hookCalled = false
        mem.addReadHook(at: 0x1000) {
            hookCalled = true
            return 0x00
        }
        #expect(mem.read(0x1000) == 0x00)
        #expect(hookCalled)
        hookCalled = false
        let data = mem.dump(from: 0x1000, length: 1)
        #expect(data == [0xAA])
        #expect(!hookCalled)
    }

    @Test func irqVectorTracking() {
        let mem = Memory()
        #expect(!mem.irqVectorWritten)
        mem.write(0xFFFE, 0x00)
        #expect(mem.irqVectorWritten)
        mem.markVectorsUnset()
        #expect(!mem.irqVectorWritten)
        mem.write(0xFFFF, 0x20)
        #expect(mem.irqVectorWritten)
    }
}
