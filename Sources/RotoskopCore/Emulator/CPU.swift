/// Results-accurate 6502 CPU (not cycle-accurate). Official opcode set only.
public final class CPU {
    public static let flagC: UInt8 = 0x01
    public static let flagZ: UInt8 = 0x02
    public static let flagI: UInt8 = 0x04
    public static let flagD: UInt8 = 0x08
    public static let flagB: UInt8 = 0x10
    public static let flagU: UInt8 = 0x20
    public static let flagV: UInt8 = 0x40
    public static let flagN: UInt8 = 0x80

    public static let stackBase: UInt16 = 0x0100
    public static let nmiVector: UInt16 = 0xFFFA
    public static let resetVector: UInt16 = 0xFFFC
    public static let irqVector: UInt16 = 0xFFFE
    public static let successAddr: UInt16 = 0xFFF9

    public let memory: Memory

    public var a: UInt8 = 0
    public var x: UInt8 = 0
    public var y: UInt8 = 0
    public var sp: UInt8 = 0xFD
    public var pc: UInt16 = 0
    public var status: UInt8 = flagU | flagI

    public private(set) var halted = false
    public private(set) var stopReason: StopReason?
    public private(set) var instructionCount = 0

    public var traceEnabled = false
    public private(set) var traceLog: [String] = []

    public var pcHooks: [UInt16: () -> Void] = [:]

    private var opcodes: [(() -> Void)?] = Array(repeating: nil, count: 256)

    public init(memory: Memory) {
        self.memory = memory
        buildOpcodeTable()
    }

    public var success: Bool { stopReason == .success }

    public func reset(clearIRQVectorTracking: Bool = true) {
        a = 0
        x = 0
        y = 0
        sp = 0xFD
        if clearIRQVectorTracking {
            memory.markVectorsUnset()
        }
        pc = memory.readWord(Self.resetVector)
        status = Self.flagU | Self.flagI
        halted = false
        stopReason = nil
        instructionCount = 0
        traceLog = []
    }

    public func requestStop() {
        forceStop(.explicitStop)
    }

    public func forceStop(_ reason: StopReason) {
        halted = true
        stopReason = reason
    }

    public func addPCHook(at addr: UInt16, hook: @escaping () -> Void) {
        pcHooks[addr] = hook
    }

    // MARK: - Flags

    public func getFlag(_ flag: UInt8) -> Bool { (status & flag) != 0 }

    public func setFlag(_ flag: UInt8, _ value: Bool) {
        if value { status |= flag } else { status &= ~flag }
    }

    public func updateNZ(_ value: UInt8) {
        setFlag(Self.flagZ, value == 0)
        setFlag(Self.flagN, (value & 0x80) != 0)
    }

    // MARK: - Stack

    public func push(_ value: UInt8) {
        memory.write(Self.stackBase &+ UInt16(sp), value)
        sp &-= 1
    }

    public func pull() -> UInt8 {
        sp &+= 1
        return memory.read(Self.stackBase &+ UInt16(sp))
    }

    public func pushWord(_ value: UInt16) {
        push(UInt8((value >> 8) & 0xFF))
        push(UInt8(value & 0xFF))
    }

    public func pullWord() -> UInt16 {
        let lo = UInt16(pull())
        let hi = UInt16(pull())
        return lo | (hi << 8)
    }

    // MARK: - Addressing

    func addrImmediate() -> UInt16 {
        let addr = pc
        pc &+= 1
        return addr
    }

    func addrZeroPage() -> UInt16 {
        let addr = UInt16(memory.read(pc))
        pc &+= 1
        return addr
    }

    func addrZeroPageX() -> UInt16 {
        let addr = UInt16(memory.read(pc) &+ x)
        pc &+= 1
        return addr
    }

    func addrZeroPageY() -> UInt16 {
        let addr = UInt16(memory.read(pc) &+ y)
        pc &+= 1
        return addr
    }

    func addrAbsolute() -> UInt16 {
        let addr = memory.readWord(pc)
        pc &+= 2
        return addr
    }

    func addrAbsoluteX() -> UInt16 {
        let base = memory.readWord(pc)
        pc &+= 2
        return base &+ UInt16(x)
    }

    func addrAbsoluteY() -> UInt16 {
        let base = memory.readWord(pc)
        pc &+= 2
        return base &+ UInt16(y)
    }

    func addrIndirect() -> UInt16 {
        let ptr = memory.readWord(pc)
        pc &+= 2
        // Classic 6502 JMP ($xxFF) page-wrap bug
        if (ptr & 0xFF) == 0xFF {
            let lo = UInt16(memory.read(ptr))
            let hi = UInt16(memory.read(ptr & 0xFF00))
            return lo | (hi << 8)
        }
        return memory.readWord(ptr)
    }

    func addrIndexedIndirect() -> UInt16 {
        let zp = memory.read(pc) &+ x
        pc &+= 1
        return memory.readWordZP(zp)
    }

    func addrIndirectIndexed() -> UInt16 {
        let zp = memory.read(pc)
        pc &+= 1
        let base = memory.readWordZP(zp)
        return base &+ UInt16(y)
    }

    func addrRelative() -> UInt16 {
        let offset = Int8(bitPattern: memory.read(pc))
        pc &+= 1
        return UInt16(bitPattern: Int16(bitPattern: pc) &+ Int16(offset))
    }

    // MARK: - Ops

    func opADC(_ addr: UInt16) {
        let value = memory.read(addr)
        let carry: UInt8 = getFlag(Self.flagC) ? 1 : 0
        if getFlag(Self.flagD) {
            let binaryResult = Int(a) + Int(value) + Int(carry)
            setFlag(Self.flagV, ((Int(a) ^ binaryResult) & (Int(value) ^ binaryResult) & 0x80) != 0)
            var lo = Int(a & 0x0F) + Int(value & 0x0F) + Int(carry)
            if lo > 9 { lo += 6 }
            var hi = Int(a >> 4) + Int(value >> 4) + (lo > 15 ? 1 : 0)
            if hi > 9 { hi += 6 }
            setFlag(Self.flagC, hi > 15)
            a = UInt8(((hi & 0x0F) << 4) | (lo & 0x0F))
            updateNZ(a)
        } else {
            let result = Int(a) + Int(value) + Int(carry)
            setFlag(Self.flagV, ((Int(a) ^ result) & (Int(value) ^ result) & 0x80) != 0)
            setFlag(Self.flagC, result > 0xFF)
            a = UInt8(result & 0xFF)
            updateNZ(a)
        }
    }

    func opAND(_ addr: UInt16) {
        a &= memory.read(addr)
        updateNZ(a)
    }

    func opASLAcc() {
        setFlag(Self.flagC, (a & 0x80) != 0)
        a = (a << 1) & 0xFF
        updateNZ(a)
    }

    func opASLMem(_ addr: UInt16) {
        var value = memory.read(addr)
        setFlag(Self.flagC, (value & 0x80) != 0)
        value = (value << 1) & 0xFF
        memory.write(addr, value)
        updateNZ(value)
    }

    func opBranch(_ condition: Bool) {
        let target = addrRelative()
        if condition { pc = target }
    }

    func opBIT(_ addr: UInt16) {
        let value = memory.read(addr)
        setFlag(Self.flagZ, (a & value) == 0)
        setFlag(Self.flagN, (value & 0x80) != 0)
        setFlag(Self.flagV, (value & 0x40) != 0)
    }

    func opBRK() {
        // Unhandled BRK: IRQ vector never written since reset
        if !memory.irqVectorWritten {
            halted = true
            stopReason = .unhandledBRK
            return
        }
        pc &+= 1 // skip signature byte
        pushWord(pc)
        push(status | Self.flagB | Self.flagU)
        setFlag(Self.flagI, true)
        pc = memory.readWord(Self.irqVector)
    }

    func opCMP(_ addr: UInt16, reg: UInt8) {
        let value = memory.read(addr)
        let result = Int(reg) - Int(value)
        setFlag(Self.flagC, reg >= value)
        updateNZ(UInt8(result & 0xFF))
    }

    func opDECMem(_ addr: UInt16) {
        let value = memory.read(addr) &- 1
        memory.write(addr, value)
        updateNZ(value)
    }

    func opEOR(_ addr: UInt16) {
        a ^= memory.read(addr)
        updateNZ(a)
    }

    func opINCMem(_ addr: UInt16) {
        let value = memory.read(addr) &+ 1
        memory.write(addr, value)
        updateNZ(value)
    }

    func opJMP(_ addr: UInt16) { pc = addr }

    func opJSR(_ addr: UInt16) {
        pushWord(pc &- 1)
        pc = addr
    }

    func opLDA(_ addr: UInt16) {
        a = memory.read(addr)
        updateNZ(a)
    }

    func opLDX(_ addr: UInt16) {
        x = memory.read(addr)
        updateNZ(x)
    }

    func opLDY(_ addr: UInt16) {
        y = memory.read(addr)
        updateNZ(y)
    }

    func opLSRAcc() {
        setFlag(Self.flagC, (a & 0x01) != 0)
        a >>= 1
        updateNZ(a)
    }

    func opLSRMem(_ addr: UInt16) {
        var value = memory.read(addr)
        setFlag(Self.flagC, (value & 0x01) != 0)
        value >>= 1
        memory.write(addr, value)
        updateNZ(value)
    }

    func opORA(_ addr: UInt16) {
        a |= memory.read(addr)
        updateNZ(a)
    }

    func opROLAcc() {
        let carry: UInt8 = getFlag(Self.flagC) ? 1 : 0
        setFlag(Self.flagC, (a & 0x80) != 0)
        a = ((a << 1) | carry) & 0xFF
        updateNZ(a)
    }

    func opROLMem(_ addr: UInt16) {
        var value = memory.read(addr)
        let carry: UInt8 = getFlag(Self.flagC) ? 1 : 0
        setFlag(Self.flagC, (value & 0x80) != 0)
        value = ((value << 1) | carry) & 0xFF
        memory.write(addr, value)
        updateNZ(value)
    }

    func opRORAcc() {
        let carry: UInt8 = getFlag(Self.flagC) ? 0x80 : 0
        setFlag(Self.flagC, (a & 0x01) != 0)
        a = (a >> 1) | carry
        updateNZ(a)
    }

    func opRORMem(_ addr: UInt16) {
        var value = memory.read(addr)
        let carry: UInt8 = getFlag(Self.flagC) ? 0x80 : 0
        setFlag(Self.flagC, (value & 0x01) != 0)
        value = (value >> 1) | carry
        memory.write(addr, value)
        updateNZ(value)
    }

    func opRTI() {
        status = (pull() | Self.flagU) & ~Self.flagB
        pc = pullWord()
    }

    public func opRTS() {
        pc = pullWord() &+ 1
    }

    func opSBC(_ addr: UInt16) {
        let value = memory.read(addr)
        let carry: UInt8 = getFlag(Self.flagC) ? 1 : 0
        if getFlag(Self.flagD) {
            let binaryResult = Int(a) - Int(value) - (1 - Int(carry))
            setFlag(Self.flagV, ((Int(a) ^ binaryResult) & (~Int(value) ^ binaryResult) & 0x80) != 0)
            var lo = Int(a & 0x0F) - Int(value & 0x0F) - (1 - Int(carry))
            if lo < 0 { lo -= 6 }
            var hi = Int(a >> 4) - Int(value >> 4) - (lo < 0 ? 1 : 0)
            if hi < 0 { hi -= 6 }
            setFlag(Self.flagC, hi >= 0)
            a = UInt8(((hi & 0x0F) << 4) | (lo & 0x0F))
            updateNZ(a)
        } else {
            let result = Int(a) - Int(value) - (1 - Int(carry))
            setFlag(Self.flagV, ((Int(a) ^ result) & (~Int(value) ^ result) & 0x80) != 0)
            setFlag(Self.flagC, result >= 0)
            a = UInt8(result & 0xFF)
            updateNZ(a)
        }
    }

    func opSTA(_ addr: UInt16) { memory.write(addr, a) }
    func opSTX(_ addr: UInt16) { memory.write(addr, x) }
    func opSTY(_ addr: UInt16) { memory.write(addr, y) }

    // MARK: - Opcode table

    private func buildOpcodeTable() {
        // ADC
        opcodes[0x69] = { [unowned self] in self.opADC(self.addrImmediate()) }
        opcodes[0x65] = { [unowned self] in self.opADC(self.addrZeroPage()) }
        opcodes[0x75] = { [unowned self] in self.opADC(self.addrZeroPageX()) }
        opcodes[0x6D] = { [unowned self] in self.opADC(self.addrAbsolute()) }
        opcodes[0x7D] = { [unowned self] in self.opADC(self.addrAbsoluteX()) }
        opcodes[0x79] = { [unowned self] in self.opADC(self.addrAbsoluteY()) }
        opcodes[0x61] = { [unowned self] in self.opADC(self.addrIndexedIndirect()) }
        opcodes[0x71] = { [unowned self] in self.opADC(self.addrIndirectIndexed()) }

        // AND
        opcodes[0x29] = { [unowned self] in self.opAND(self.addrImmediate()) }
        opcodes[0x25] = { [unowned self] in self.opAND(self.addrZeroPage()) }
        opcodes[0x35] = { [unowned self] in self.opAND(self.addrZeroPageX()) }
        opcodes[0x2D] = { [unowned self] in self.opAND(self.addrAbsolute()) }
        opcodes[0x3D] = { [unowned self] in self.opAND(self.addrAbsoluteX()) }
        opcodes[0x39] = { [unowned self] in self.opAND(self.addrAbsoluteY()) }
        opcodes[0x21] = { [unowned self] in self.opAND(self.addrIndexedIndirect()) }
        opcodes[0x31] = { [unowned self] in self.opAND(self.addrIndirectIndexed()) }

        // ASL
        opcodes[0x0A] = { [unowned self] in self.opASLAcc() }
        opcodes[0x06] = { [unowned self] in self.opASLMem(self.addrZeroPage()) }
        opcodes[0x16] = { [unowned self] in self.opASLMem(self.addrZeroPageX()) }
        opcodes[0x0E] = { [unowned self] in self.opASLMem(self.addrAbsolute()) }
        opcodes[0x1E] = { [unowned self] in self.opASLMem(self.addrAbsoluteX()) }

        // Branches
        opcodes[0x90] = { [unowned self] in self.opBranch(!self.getFlag(Self.flagC)) }
        opcodes[0xB0] = { [unowned self] in self.opBranch(self.getFlag(Self.flagC)) }
        opcodes[0xF0] = { [unowned self] in self.opBranch(self.getFlag(Self.flagZ)) }
        opcodes[0x30] = { [unowned self] in self.opBranch(self.getFlag(Self.flagN)) }
        opcodes[0xD0] = { [unowned self] in self.opBranch(!self.getFlag(Self.flagZ)) }
        opcodes[0x10] = { [unowned self] in self.opBranch(!self.getFlag(Self.flagN)) }
        opcodes[0x50] = { [unowned self] in self.opBranch(!self.getFlag(Self.flagV)) }
        opcodes[0x70] = { [unowned self] in self.opBranch(self.getFlag(Self.flagV)) }

        // BIT / BRK
        opcodes[0x24] = { [unowned self] in self.opBIT(self.addrZeroPage()) }
        opcodes[0x2C] = { [unowned self] in self.opBIT(self.addrAbsolute()) }
        opcodes[0x00] = { [unowned self] in self.opBRK() }

        // Flags
        opcodes[0x18] = { [unowned self] in self.setFlag(Self.flagC, false) }
        opcodes[0xD8] = { [unowned self] in self.setFlag(Self.flagD, false) }
        opcodes[0x58] = { [unowned self] in self.setFlag(Self.flagI, false) }
        opcodes[0xB8] = { [unowned self] in self.setFlag(Self.flagV, false) }
        opcodes[0x38] = { [unowned self] in self.setFlag(Self.flagC, true) }
        opcodes[0xF8] = { [unowned self] in self.setFlag(Self.flagD, true) }
        opcodes[0x78] = { [unowned self] in self.setFlag(Self.flagI, true) }

        // CMP / CPX / CPY
        opcodes[0xC9] = { [unowned self] in self.opCMP(self.addrImmediate(), reg: self.a) }
        opcodes[0xC5] = { [unowned self] in self.opCMP(self.addrZeroPage(), reg: self.a) }
        opcodes[0xD5] = { [unowned self] in self.opCMP(self.addrZeroPageX(), reg: self.a) }
        opcodes[0xCD] = { [unowned self] in self.opCMP(self.addrAbsolute(), reg: self.a) }
        opcodes[0xDD] = { [unowned self] in self.opCMP(self.addrAbsoluteX(), reg: self.a) }
        opcodes[0xD9] = { [unowned self] in self.opCMP(self.addrAbsoluteY(), reg: self.a) }
        opcodes[0xC1] = { [unowned self] in self.opCMP(self.addrIndexedIndirect(), reg: self.a) }
        opcodes[0xD1] = { [unowned self] in self.opCMP(self.addrIndirectIndexed(), reg: self.a) }
        opcodes[0xE0] = { [unowned self] in self.opCMP(self.addrImmediate(), reg: self.x) }
        opcodes[0xE4] = { [unowned self] in self.opCMP(self.addrZeroPage(), reg: self.x) }
        opcodes[0xEC] = { [unowned self] in self.opCMP(self.addrAbsolute(), reg: self.x) }
        opcodes[0xC0] = { [unowned self] in self.opCMP(self.addrImmediate(), reg: self.y) }
        opcodes[0xC4] = { [unowned self] in self.opCMP(self.addrZeroPage(), reg: self.y) }
        opcodes[0xCC] = { [unowned self] in self.opCMP(self.addrAbsolute(), reg: self.y) }

        // DEC / DEX / DEY
        opcodes[0xC6] = { [unowned self] in self.opDECMem(self.addrZeroPage()) }
        opcodes[0xD6] = { [unowned self] in self.opDECMem(self.addrZeroPageX()) }
        opcodes[0xCE] = { [unowned self] in self.opDECMem(self.addrAbsolute()) }
        opcodes[0xDE] = { [unowned self] in self.opDECMem(self.addrAbsoluteX()) }
        opcodes[0xCA] = { [unowned self] in self.x &-= 1; self.updateNZ(self.x) }
        opcodes[0x88] = { [unowned self] in self.y &-= 1; self.updateNZ(self.y) }

        // EOR
        opcodes[0x49] = { [unowned self] in self.opEOR(self.addrImmediate()) }
        opcodes[0x45] = { [unowned self] in self.opEOR(self.addrZeroPage()) }
        opcodes[0x55] = { [unowned self] in self.opEOR(self.addrZeroPageX()) }
        opcodes[0x4D] = { [unowned self] in self.opEOR(self.addrAbsolute()) }
        opcodes[0x5D] = { [unowned self] in self.opEOR(self.addrAbsoluteX()) }
        opcodes[0x59] = { [unowned self] in self.opEOR(self.addrAbsoluteY()) }
        opcodes[0x41] = { [unowned self] in self.opEOR(self.addrIndexedIndirect()) }
        opcodes[0x51] = { [unowned self] in self.opEOR(self.addrIndirectIndexed()) }

        // INC / INX / INY
        opcodes[0xE6] = { [unowned self] in self.opINCMem(self.addrZeroPage()) }
        opcodes[0xF6] = { [unowned self] in self.opINCMem(self.addrZeroPageX()) }
        opcodes[0xEE] = { [unowned self] in self.opINCMem(self.addrAbsolute()) }
        opcodes[0xFE] = { [unowned self] in self.opINCMem(self.addrAbsoluteX()) }
        opcodes[0xE8] = { [unowned self] in self.x &+= 1; self.updateNZ(self.x) }
        opcodes[0xC8] = { [unowned self] in self.y &+= 1; self.updateNZ(self.y) }

        // JMP / JSR
        opcodes[0x4C] = { [unowned self] in self.opJMP(self.addrAbsolute()) }
        opcodes[0x6C] = { [unowned self] in self.opJMP(self.addrIndirect()) }
        opcodes[0x20] = { [unowned self] in self.opJSR(self.addrAbsolute()) }

        // LDA
        opcodes[0xA9] = { [unowned self] in self.opLDA(self.addrImmediate()) }
        opcodes[0xA5] = { [unowned self] in self.opLDA(self.addrZeroPage()) }
        opcodes[0xB5] = { [unowned self] in self.opLDA(self.addrZeroPageX()) }
        opcodes[0xAD] = { [unowned self] in self.opLDA(self.addrAbsolute()) }
        opcodes[0xBD] = { [unowned self] in self.opLDA(self.addrAbsoluteX()) }
        opcodes[0xB9] = { [unowned self] in self.opLDA(self.addrAbsoluteY()) }
        opcodes[0xA1] = { [unowned self] in self.opLDA(self.addrIndexedIndirect()) }
        opcodes[0xB1] = { [unowned self] in self.opLDA(self.addrIndirectIndexed()) }

        // LDX / LDY
        opcodes[0xA2] = { [unowned self] in self.opLDX(self.addrImmediate()) }
        opcodes[0xA6] = { [unowned self] in self.opLDX(self.addrZeroPage()) }
        opcodes[0xB6] = { [unowned self] in self.opLDX(self.addrZeroPageY()) }
        opcodes[0xAE] = { [unowned self] in self.opLDX(self.addrAbsolute()) }
        opcodes[0xBE] = { [unowned self] in self.opLDX(self.addrAbsoluteY()) }
        opcodes[0xA0] = { [unowned self] in self.opLDY(self.addrImmediate()) }
        opcodes[0xA4] = { [unowned self] in self.opLDY(self.addrZeroPage()) }
        opcodes[0xB4] = { [unowned self] in self.opLDY(self.addrZeroPageX()) }
        opcodes[0xAC] = { [unowned self] in self.opLDY(self.addrAbsolute()) }
        opcodes[0xBC] = { [unowned self] in self.opLDY(self.addrAbsoluteX()) }

        // LSR
        opcodes[0x4A] = { [unowned self] in self.opLSRAcc() }
        opcodes[0x46] = { [unowned self] in self.opLSRMem(self.addrZeroPage()) }
        opcodes[0x56] = { [unowned self] in self.opLSRMem(self.addrZeroPageX()) }
        opcodes[0x4E] = { [unowned self] in self.opLSRMem(self.addrAbsolute()) }
        opcodes[0x5E] = { [unowned self] in self.opLSRMem(self.addrAbsoluteX()) }

        // NOP
        opcodes[0xEA] = { }

        // ORA
        opcodes[0x09] = { [unowned self] in self.opORA(self.addrImmediate()) }
        opcodes[0x05] = { [unowned self] in self.opORA(self.addrZeroPage()) }
        opcodes[0x15] = { [unowned self] in self.opORA(self.addrZeroPageX()) }
        opcodes[0x0D] = { [unowned self] in self.opORA(self.addrAbsolute()) }
        opcodes[0x1D] = { [unowned self] in self.opORA(self.addrAbsoluteX()) }
        opcodes[0x19] = { [unowned self] in self.opORA(self.addrAbsoluteY()) }
        opcodes[0x01] = { [unowned self] in self.opORA(self.addrIndexedIndirect()) }
        opcodes[0x11] = { [unowned self] in self.opORA(self.addrIndirectIndexed()) }

        // Stack
        opcodes[0x48] = { [unowned self] in self.push(self.a) }
        opcodes[0x08] = { [unowned self] in self.push(self.status | Self.flagB | Self.flagU) }
        opcodes[0x68] = { [unowned self] in self.a = self.pull(); self.updateNZ(self.a) }
        opcodes[0x28] = { [unowned self] in self.status = (self.pull() | Self.flagU) & ~Self.flagB }

        // ROL / ROR
        opcodes[0x2A] = { [unowned self] in self.opROLAcc() }
        opcodes[0x26] = { [unowned self] in self.opROLMem(self.addrZeroPage()) }
        opcodes[0x36] = { [unowned self] in self.opROLMem(self.addrZeroPageX()) }
        opcodes[0x2E] = { [unowned self] in self.opROLMem(self.addrAbsolute()) }
        opcodes[0x3E] = { [unowned self] in self.opROLMem(self.addrAbsoluteX()) }
        opcodes[0x6A] = { [unowned self] in self.opRORAcc() }
        opcodes[0x66] = { [unowned self] in self.opRORMem(self.addrZeroPage()) }
        opcodes[0x76] = { [unowned self] in self.opRORMem(self.addrZeroPageX()) }
        opcodes[0x6E] = { [unowned self] in self.opRORMem(self.addrAbsolute()) }
        opcodes[0x7E] = { [unowned self] in self.opRORMem(self.addrAbsoluteX()) }

        // RTI / RTS
        opcodes[0x40] = { [unowned self] in self.opRTI() }
        opcodes[0x60] = { [unowned self] in self.opRTS() }

        // SBC
        opcodes[0xE9] = { [unowned self] in self.opSBC(self.addrImmediate()) }
        opcodes[0xE5] = { [unowned self] in self.opSBC(self.addrZeroPage()) }
        opcodes[0xF5] = { [unowned self] in self.opSBC(self.addrZeroPageX()) }
        opcodes[0xED] = { [unowned self] in self.opSBC(self.addrAbsolute()) }
        opcodes[0xFD] = { [unowned self] in self.opSBC(self.addrAbsoluteX()) }
        opcodes[0xF9] = { [unowned self] in self.opSBC(self.addrAbsoluteY()) }
        opcodes[0xE1] = { [unowned self] in self.opSBC(self.addrIndexedIndirect()) }
        opcodes[0xF1] = { [unowned self] in self.opSBC(self.addrIndirectIndexed()) }

        // STA / STX / STY
        opcodes[0x85] = { [unowned self] in self.opSTA(self.addrZeroPage()) }
        opcodes[0x95] = { [unowned self] in self.opSTA(self.addrZeroPageX()) }
        opcodes[0x8D] = { [unowned self] in self.opSTA(self.addrAbsolute()) }
        opcodes[0x9D] = { [unowned self] in self.opSTA(self.addrAbsoluteX()) }
        opcodes[0x99] = { [unowned self] in self.opSTA(self.addrAbsoluteY()) }
        opcodes[0x81] = { [unowned self] in self.opSTA(self.addrIndexedIndirect()) }
        opcodes[0x91] = { [unowned self] in self.opSTA(self.addrIndirectIndexed()) }
        opcodes[0x86] = { [unowned self] in self.opSTX(self.addrZeroPage()) }
        opcodes[0x96] = { [unowned self] in self.opSTX(self.addrZeroPageY()) }
        opcodes[0x8E] = { [unowned self] in self.opSTX(self.addrAbsolute()) }
        opcodes[0x84] = { [unowned self] in self.opSTY(self.addrZeroPage()) }
        opcodes[0x94] = { [unowned self] in self.opSTY(self.addrZeroPageX()) }
        opcodes[0x8C] = { [unowned self] in self.opSTY(self.addrAbsolute()) }

        // Transfers
        opcodes[0xAA] = { [unowned self] in self.x = self.a; self.updateNZ(self.x) }
        opcodes[0xA8] = { [unowned self] in self.y = self.a; self.updateNZ(self.y) }
        opcodes[0xBA] = { [unowned self] in self.x = self.sp; self.updateNZ(self.x) }
        opcodes[0x8A] = { [unowned self] in self.a = self.x; self.updateNZ(self.a) }
        opcodes[0x9A] = { [unowned self] in self.sp = self.x }
        opcodes[0x98] = { [unowned self] in self.a = self.y; self.updateNZ(self.a) }
    }

    // MARK: - Disassembly / trace

    private static let opcodeNames: [UInt8: (String, String)] = {
        var m: [UInt8: (String, String)] = [:]
        let entries: [(UInt8, String, String)] = [
            (0x69, "ADC", "#"), (0x65, "ADC", "zp"), (0x75, "ADC", "zp,x"),
            (0x6D, "ADC", "abs"), (0x7D, "ADC", "abs,x"), (0x79, "ADC", "abs,y"),
            (0x61, "ADC", "(zp,x)"), (0x71, "ADC", "(zp),y"),
            (0x29, "AND", "#"), (0x25, "AND", "zp"), (0x35, "AND", "zp,x"),
            (0x2D, "AND", "abs"), (0x3D, "AND", "abs,x"), (0x39, "AND", "abs,y"),
            (0x21, "AND", "(zp,x)"), (0x31, "AND", "(zp),y"),
            (0x0A, "ASL", "A"), (0x06, "ASL", "zp"), (0x16, "ASL", "zp,x"),
            (0x0E, "ASL", "abs"), (0x1E, "ASL", "abs,x"),
            (0x90, "BCC", "rel"), (0xB0, "BCS", "rel"), (0xF0, "BEQ", "rel"),
            (0x30, "BMI", "rel"), (0xD0, "BNE", "rel"), (0x10, "BPL", "rel"),
            (0x50, "BVC", "rel"), (0x70, "BVS", "rel"),
            (0x24, "BIT", "zp"), (0x2C, "BIT", "abs"),
            (0x00, "BRK", ""), (0x18, "CLC", ""), (0xD8, "CLD", ""),
            (0x58, "CLI", ""), (0xB8, "CLV", ""),
            (0xC9, "CMP", "#"), (0xC5, "CMP", "zp"), (0xD5, "CMP", "zp,x"),
            (0xCD, "CMP", "abs"), (0xDD, "CMP", "abs,x"), (0xD9, "CMP", "abs,y"),
            (0xC1, "CMP", "(zp,x)"), (0xD1, "CMP", "(zp),y"),
            (0xE0, "CPX", "#"), (0xE4, "CPX", "zp"), (0xEC, "CPX", "abs"),
            (0xC0, "CPY", "#"), (0xC4, "CPY", "zp"), (0xCC, "CPY", "abs"),
            (0xC6, "DEC", "zp"), (0xD6, "DEC", "zp,x"), (0xCE, "DEC", "abs"), (0xDE, "DEC", "abs,x"),
            (0xCA, "DEX", ""), (0x88, "DEY", ""),
            (0x49, "EOR", "#"), (0x45, "EOR", "zp"), (0x55, "EOR", "zp,x"),
            (0x4D, "EOR", "abs"), (0x5D, "EOR", "abs,x"), (0x59, "EOR", "abs,y"),
            (0x41, "EOR", "(zp,x)"), (0x51, "EOR", "(zp),y"),
            (0xE6, "INC", "zp"), (0xF6, "INC", "zp,x"), (0xEE, "INC", "abs"), (0xFE, "INC", "abs,x"),
            (0xE8, "INX", ""), (0xC8, "INY", ""),
            (0x4C, "JMP", "abs"), (0x6C, "JMP", "(abs)"), (0x20, "JSR", "abs"),
            (0xA9, "LDA", "#"), (0xA5, "LDA", "zp"), (0xB5, "LDA", "zp,x"),
            (0xAD, "LDA", "abs"), (0xBD, "LDA", "abs,x"), (0xB9, "LDA", "abs,y"),
            (0xA1, "LDA", "(zp,x)"), (0xB1, "LDA", "(zp),y"),
            (0xA2, "LDX", "#"), (0xA6, "LDX", "zp"), (0xB6, "LDX", "zp,y"),
            (0xAE, "LDX", "abs"), (0xBE, "LDX", "abs,y"),
            (0xA0, "LDY", "#"), (0xA4, "LDY", "zp"), (0xB4, "LDY", "zp,x"),
            (0xAC, "LDY", "abs"), (0xBC, "LDY", "abs,x"),
            (0x4A, "LSR", "A"), (0x46, "LSR", "zp"), (0x56, "LSR", "zp,x"),
            (0x4E, "LSR", "abs"), (0x5E, "LSR", "abs,x"),
            (0xEA, "NOP", ""),
            (0x09, "ORA", "#"), (0x05, "ORA", "zp"), (0x15, "ORA", "zp,x"),
            (0x0D, "ORA", "abs"), (0x1D, "ORA", "abs,x"), (0x19, "ORA", "abs,y"),
            (0x01, "ORA", "(zp,x)"), (0x11, "ORA", "(zp),y"),
            (0x48, "PHA", ""), (0x08, "PHP", ""), (0x68, "PLA", ""), (0x28, "PLP", ""),
            (0x2A, "ROL", "A"), (0x26, "ROL", "zp"), (0x36, "ROL", "zp,x"),
            (0x2E, "ROL", "abs"), (0x3E, "ROL", "abs,x"),
            (0x6A, "ROR", "A"), (0x66, "ROR", "zp"), (0x76, "ROR", "zp,x"),
            (0x6E, "ROR", "abs"), (0x7E, "ROR", "abs,x"),
            (0x40, "RTI", ""), (0x60, "RTS", ""),
            (0xE9, "SBC", "#"), (0xE5, "SBC", "zp"), (0xF5, "SBC", "zp,x"),
            (0xED, "SBC", "abs"), (0xFD, "SBC", "abs,x"), (0xF9, "SBC", "abs,y"),
            (0xE1, "SBC", "(zp,x)"), (0xF1, "SBC", "(zp),y"),
            (0x38, "SEC", ""), (0xF8, "SED", ""), (0x78, "SEI", ""),
            (0x85, "STA", "zp"), (0x95, "STA", "zp,x"), (0x8D, "STA", "abs"),
            (0x9D, "STA", "abs,x"), (0x99, "STA", "abs,y"),
            (0x81, "STA", "(zp,x)"), (0x91, "STA", "(zp),y"),
            (0x86, "STX", "zp"), (0x96, "STX", "zp,y"), (0x8E, "STX", "abs"),
            (0x84, "STY", "zp"), (0x94, "STY", "zp,x"), (0x8C, "STY", "abs"),
            (0xAA, "TAX", ""), (0xA8, "TAY", ""), (0xBA, "TSX", ""),
            (0x8A, "TXA", ""), (0x9A, "TXS", ""), (0x98, "TYA", ""),
        ]
        for (op, name, mode) in entries { m[op] = (name, mode) }
        return m
    }()

    public func disassemble(at addr: UInt16) -> (String, Int) {
        let opcode = memory.read(addr)
        guard let (name, mode) = Self.opcodeNames[opcode] else {
            return (String(format: "???  ($%02X)", opcode), 1)
        }
        switch mode {
        case "": return (name, 1)
        case "A": return ("\(name) A", 1)
        case "#":
            return (String(format: "%@ #$%02X", name, memory.read(addr &+ 1)), 2)
        case "zp":
            return (String(format: "%@ $%02X", name, memory.read(addr &+ 1)), 2)
        case "zp,x":
            return (String(format: "%@ $%02X,X", name, memory.read(addr &+ 1)), 2)
        case "zp,y":
            return (String(format: "%@ $%02X,Y", name, memory.read(addr &+ 1)), 2)
        case "abs":
            return (String(format: "%@ $%04X", name, memory.readWord(addr &+ 1)), 3)
        case "abs,x":
            return (String(format: "%@ $%04X,X", name, memory.readWord(addr &+ 1)), 3)
        case "abs,y":
            return (String(format: "%@ $%04X,Y", name, memory.readWord(addr &+ 1)), 3)
        case "(abs)":
            return (String(format: "%@ ($%04X)", name, memory.readWord(addr &+ 1)), 3)
        case "(zp,x)":
            return (String(format: "%@ ($%02X,X)", name, memory.read(addr &+ 1)), 2)
        case "(zp),y":
            return (String(format: "%@ ($%02X),Y", name, memory.read(addr &+ 1)), 2)
        case "rel":
            let offset = Int8(bitPattern: memory.read(addr &+ 1))
            let target = UInt16(bitPattern: Int16(bitPattern: addr &+ 2) &+ Int16(offset))
            return (String(format: "%@ $%04X", name, target), 2)
        default:
            return ("\(name) ???", 1)
        }
    }

    public func formatState() -> String {
        var flags = ""
        flags += getFlag(Self.flagN) ? "N" : "n"
        flags += getFlag(Self.flagV) ? "V" : "v"
        flags += "-"
        flags += getFlag(Self.flagB) ? "B" : "b"
        flags += getFlag(Self.flagD) ? "D" : "d"
        flags += getFlag(Self.flagI) ? "I" : "i"
        flags += getFlag(Self.flagZ) ? "Z" : "z"
        flags += getFlag(Self.flagC) ? "C" : "c"
        return String(format: "A=$%02X X=$%02X Y=$%02X SP=$%02X [%@]", a, x, y, sp, flags)
    }

    public func registerDump() -> String {
        String(
            format: "A=$%02X X=$%02X Y=$%02X SP=$%02X PC=$%04X status=$%02X %@",
            a, x, y, sp, pc, status, formatState()
        )
    }

    // MARK: - Execution

    /// Execute one instruction. Returns `false` if halted.
    @discardableResult
    public func step() -> Bool {
        if halted { return false }

        if pc == Self.successAddr {
            halted = true
            stopReason = .success
            return false
        }

        if let hook = pcHooks[pc] {
            hook()
            instructionCount += 1
            return !halted
        }

        let pcBefore = pc
        let opcode = memory.read(pc)
        pc &+= 1

        guard let op = opcodes[Int(opcode)] else {
            halted = true
            stopReason = .illegalOpcode(opcode)
            pc = pcBefore
            return false
        }

        if traceEnabled {
            let (disasm, _) = disassemble(at: pcBefore)
            let padded = disasm.padding(toLength: 20, withPad: " ", startingAt: 0)
            traceLog.append(String(format: "$%04X: %@  %@", pcBefore, padded, formatState()))
        }

        op()
        instructionCount += 1
        return !halted
    }

    /// Run until halt or instruction limit. Sets `stopReason`.
    @discardableResult
    public func run(maxInstructions: Int = 1000) -> StopReason {
        while instructionCount < maxInstructions {
            if !step() { break }
        }
        if !halted && instructionCount >= maxInstructions {
            halted = true
            stopReason = .instructionLimit
        }
        return stopReason ?? .instructionLimit
    }
}
