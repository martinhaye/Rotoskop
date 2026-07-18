import Testing
@testable import RotoskopCore

@Suite("CPU basics")
struct CPUBasicsTests {
    @Test func initialStateAfterReset() {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        cpu.reset()
        #expect(cpu.a == 0)
        #expect(cpu.x == 0)
        #expect(cpu.y == 0)
        #expect(cpu.sp == 0xFD)
        #expect(cpu.pc == 0x1000)
    }

    @Test func illegalOpcodeStops() {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        mem.write(0x1000, 0x02)
        cpu.reset()
        #expect(!cpu.step())
        #expect(cpu.stopReason == .illegalOpcode(0x02))
    }

    @Test func successOnFFF9() {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0xFFF9)
        cpu.reset()
        #expect(!cpu.step())
        #expect(cpu.stopReason == .success)
    }
}

@Suite("Flags & stack")
struct FlagStackTests {
    @Test func flagsAndNZ() {
        let cpu = CPU(memory: Memory())
        cpu.setFlag(CPU.flagC, true)
        #expect(cpu.getFlag(CPU.flagC))
        cpu.setFlag(CPU.flagC, false)
        #expect(!cpu.getFlag(CPU.flagC))
        cpu.updateNZ(0)
        #expect(cpu.getFlag(CPU.flagZ))
        #expect(!cpu.getFlag(CPU.flagN))
        cpu.updateNZ(0x80)
        #expect(!cpu.getFlag(CPU.flagZ))
        #expect(cpu.getFlag(CPU.flagN))
    }

    @Test func pushPullWord() {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        cpu.sp = 0xFF
        cpu.pushWord(0x1234)
        #expect(cpu.sp == 0xFD)
        #expect(mem.read(0x01FF) == 0x12)
        #expect(mem.read(0x01FE) == 0x34)
        #expect(cpu.pullWord() == 0x1234)
        #expect(cpu.sp == 0xFF)
    }
}

@Suite("Load / store / addressing")
struct LoadStoreTests {
    private func ready() -> (Memory, CPU) {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        cpu.reset()
        return (mem, cpu)
    }

    @Test func ldaImmediate() {
        let (mem, cpu) = ready()
        mem.write(0x1000, 0xA9)
        mem.write(0x1001, 0x42)
        cpu.step()
        #expect(cpu.a == 0x42)
        #expect(cpu.pc == 0x1002)
    }

    @Test func ldaZeroPageX() {
        let (mem, cpu) = ready()
        cpu.x = 0x05
        mem.write(0x1000, 0xB5)
        mem.write(0x1001, 0x10)
        mem.write(0x0015, 0x42)
        cpu.step()
        #expect(cpu.a == 0x42)
    }

    @Test func ldaAbsoluteY() {
        let (mem, cpu) = ready()
        cpu.y = 0x05
        mem.write(0x1000, 0xB9)
        mem.write(0x1001, 0x00)
        mem.write(0x1002, 0x20)
        mem.write(0x2005, 0x42)
        cpu.step()
        #expect(cpu.a == 0x42)
    }

    @Test func ldaIndexedIndirect() {
        let (mem, cpu) = ready()
        cpu.x = 0x05
        mem.write(0x1000, 0xA1)
        mem.write(0x1001, 0x10)
        mem.write(0x0015, 0x00)
        mem.write(0x0016, 0x20)
        mem.write(0x2000, 0x42)
        cpu.step()
        #expect(cpu.a == 0x42)
    }

    @Test func ldaIndirectIndexed() {
        let (mem, cpu) = ready()
        cpu.y = 0x05
        mem.write(0x1000, 0xB1)
        mem.write(0x1001, 0x10)
        mem.write(0x0010, 0x00)
        mem.write(0x0011, 0x20)
        mem.write(0x2005, 0x42)
        cpu.step()
        #expect(cpu.a == 0x42)
    }

    @Test func staZeroPage() {
        let (mem, cpu) = ready()
        cpu.a = 0x99
        mem.write(0x1000, 0x85)
        mem.write(0x1001, 0x10)
        cpu.step()
        #expect(mem.read(0x10) == 0x99)
    }
}

@Suite("Arithmetic & branches")
struct ArithmeticTests {
    private func ready() -> (Memory, CPU) {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        cpu.reset()
        return (mem, cpu)
    }

    @Test func adcBinary() {
        let (mem, cpu) = ready()
        cpu.a = 0x10
        cpu.setFlag(CPU.flagC, false)
        mem.write(0x1000, 0x69)
        mem.write(0x1001, 0x05)
        cpu.step()
        #expect(cpu.a == 0x15)
        #expect(!cpu.getFlag(CPU.flagC))
    }

    @Test func sbcBinary() {
        let (mem, cpu) = ready()
        cpu.a = 0x50
        cpu.setFlag(CPU.flagC, true) // no borrow
        mem.write(0x1000, 0xE9)
        mem.write(0x1001, 0x20)
        cpu.step()
        #expect(cpu.a == 0x30)
        #expect(cpu.getFlag(CPU.flagC))
    }

    @Test func beqTaken() {
        let (mem, cpu) = ready()
        cpu.setFlag(CPU.flagZ, true)
        mem.write(0x1000, 0xF0)
        mem.write(0x1001, 0x05) // +5 → $1007
        cpu.step()
        #expect(cpu.pc == 0x1007)
    }

    @Test func bneNotTaken() {
        let (mem, cpu) = ready()
        cpu.setFlag(CPU.flagZ, true)
        mem.write(0x1000, 0xD0)
        mem.write(0x1001, 0x05)
        cpu.step()
        #expect(cpu.pc == 0x1002)
    }
}

@Suite("JMP / JSR / BRK")
struct ControlFlowTests {
    private func ready() -> (Memory, CPU) {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        cpu.reset()
        return (mem, cpu)
    }

    @Test func jmpAbsolute() {
        let (mem, cpu) = ready()
        mem.write(0x1000, 0x4C)
        mem.write(0x1001, 0x00)
        mem.write(0x1002, 0x20)
        cpu.step()
        #expect(cpu.pc == 0x2000)
    }

    @Test func jmpIndirectPageBug() {
        let (mem, cpu) = ready()
        // Pointer at $10FF: lo at $10FF, hi wrongly from $1000 (page wrap)
        mem.write(0x10FF, 0x34)
        mem.write(0x1000, 0x12) // bug read
        mem.write(0x1100, 0xAB) // correct would be here
        mem.write(0x2000, 0x6C)
        mem.write(0x2001, 0xFF)
        mem.write(0x2002, 0x10)
        cpu.pc = 0x2000
        cpu.step()
        #expect(cpu.pc == 0x1234)
    }

    @Test func jsrRts() {
        let (mem, cpu) = ready()
        mem.write(0x1000, 0x20)
        mem.write(0x1001, 0x00)
        mem.write(0x1002, 0x20)
        mem.write(0x2000, 0x60) // RTS
        cpu.step()
        #expect(cpu.pc == 0x2000)
        cpu.step()
        #expect(cpu.pc == 0x1003)
    }

    @Test func unhandledBRK() {
        let (mem, cpu) = ready()
        #expect(!mem.irqVectorWritten)
        mem.write(0x1000, 0x00) // BRK
        cpu.step()
        #expect(cpu.stopReason == .unhandledBRK)
    }

    @Test func handledBRK() {
        let (mem, cpu) = ready()
        mem.writeWord(0xFFFE, 0x2000)
        #expect(mem.irqVectorWritten)
        mem.write(0x1000, 0x00)
        mem.write(0x1001, 0x42)
        cpu.sp = 0xFF
        cpu.step()
        #expect(cpu.pc == 0x2000)
        #expect(cpu.sp == 0xFC)
        #expect(mem.read(0x01FE) == 0x02)
        #expect(mem.read(0x01FF) == 0x10)
        #expect(cpu.getFlag(CPU.flagI))
    }
}

@Suite("Instruction limit")
struct RunLimitTests {
    @Test func hitsLimit() {
        let mem = Memory()
        let cpu = CPU(memory: mem)
        mem.setResetVector(0x1000)
        mem.write(0x1000, 0xEA) // NOP
        mem.write(0x1001, 0x4C)
        mem.write(0x1002, 0x00)
        mem.write(0x1003, 0x10) // JMP $1000
        cpu.reset()
        let reason = cpu.run(maxInstructions: 50)
        #expect(reason == .instructionLimit)
        #expect(cpu.instructionCount == 50)
    }
}
