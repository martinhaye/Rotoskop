//
//  Instructions.swift
//  RotoskopEmulator
//
//  Reusable building blocks for instruction behaviour. Each 6502 instruction
//  family (loads, arithmetic, compares, branches, shifts, …) collapses to one
//  of these helpers, so the dispatch table in `InstructionSet.swift` stays
//  declarative and porting new opcodes is mostly picking the right helper.
//

extension CPU6502 {

    // MARK: Loads / stores

    func loadA(_ operand: Operand) {
        a = loadOperand(operand)
        p.updateZeroNegative(a)
    }

    func loadX(_ operand: Operand) {
        x = loadOperand(operand)
        p.updateZeroNegative(x)
    }

    func loadY(_ operand: Operand) {
        y = loadOperand(operand)
        p.updateZeroNegative(y)
    }

    func store(_ value: UInt8, _ operand: Operand) {
        if let addr = effectiveAddress(operand) { bus.write(addr, value) }
    }

    // MARK: Register transfers

    func transfer(_ value: UInt8, updatingFlags: Bool = true) -> UInt8 {
        if updatingFlags { p.updateZeroNegative(value) }
        return value
    }

    // MARK: Increment / decrement

    func increment(memory operand: Operand) {
        guard let addr = effectiveAddress(operand) else { return }
        let result = bus.read(addr) &+ 1
        bus.write(addr, result)
        p.updateZeroNegative(result)
    }

    func decrement(memory operand: Operand) {
        guard let addr = effectiveAddress(operand) else { return }
        let result = bus.read(addr) &- 1
        bus.write(addr, result)
        p.updateZeroNegative(result)
    }

    // MARK: Logic

    func and(_ operand: Operand) {
        a &= loadOperand(operand)
        p.updateZeroNegative(a)
    }

    func ora(_ operand: Operand) {
        a |= loadOperand(operand)
        p.updateZeroNegative(a)
    }

    func eor(_ operand: Operand) {
        a ^= loadOperand(operand)
        p.updateZeroNegative(a)
    }

    func bit(_ operand: Operand) {
        let value = loadOperand(operand)
        p.set(.zero, (a & value) == 0)
        p.set(.overflow, value & 0x40 != 0)
        p.set(.negative, value & 0x80 != 0)
    }

    // MARK: Arithmetic

    /// Add with carry. Handles both binary and (BCD) decimal mode.
    func adc(_ operand: Operand) {
        let value = loadOperand(operand)
        addToAccumulator(value)
    }

    /// Subtract with carry — implemented as ADC of the ones' complement, which
    /// is exactly how the hardware does it in binary mode.
    func sbc(_ operand: Operand) {
        let value = loadOperand(operand)
        addToAccumulator(value ^ 0xFF)
    }

    private func addToAccumulator(_ value: UInt8) {
        let carryIn: UInt16 = p.contains(.carry) ? 1 : 0

        if p.contains(.decimal) {
            // Binary-coded-decimal addition (NMOS behaviour, simplified).
            var lo = UInt16(a & 0x0F) + UInt16(value & 0x0F) + carryIn
            var hi = UInt16(a >> 4) + UInt16(value >> 4)
            if lo > 9 { lo += 6; hi += 1 }
            if hi > 9 { hi += 6 }
            let result = UInt8(((hi << 4) | (lo & 0x0F)) & 0xFF)
            p.set(.carry, hi > 0x0F)
            p.updateZeroNegative(result)
            a = result
            return
        }

        let sum = UInt16(a) + UInt16(value) + carryIn
        let result = UInt8(sum & 0xFF)
        p.set(.carry, sum > 0xFF)
        // Overflow: set when the sign of both inputs matches but differs from
        // the result's sign.
        p.set(.overflow, ((a ^ result) & (value ^ result) & 0x80) != 0)
        p.updateZeroNegative(result)
        a = result
    }

    // MARK: Compares

    func compare(_ register: UInt8, _ operand: Operand) {
        let value = loadOperand(operand)
        let result = register &- value
        p.set(.carry, register >= value)
        p.updateZeroNegative(result)
    }

    // MARK: Shifts / rotates

    /// Applies a shift/rotate to either the accumulator (accumulator mode) or a
    /// memory location, then updates flags. `op` receives the input byte and the
    /// incoming carry and returns the result plus the outgoing carry.
    func shift(_ operand: Operand, _ op: (UInt8, Bool) -> (UInt8, Bool)) {
        let carryIn = p.contains(.carry)
        if let addr = effectiveAddress(operand) {
            let (result, carryOut) = op(bus.read(addr), carryIn)
            bus.write(addr, result)
            p.set(.carry, carryOut)
            p.updateZeroNegative(result)
        } else {
            let (result, carryOut) = op(a, carryIn)
            a = result
            p.set(.carry, carryOut)
            p.updateZeroNegative(result)
        }
    }

    // MARK: Branches

    /// Branches to the operand's target when `condition` holds.
    func branch(_ condition: Bool, _ operand: Operand) {
        guard condition, let target = effectiveAddress(operand) else { return }
        pc = target
    }

    // MARK: Subroutines / interrupts

    func jsr(_ operand: Operand) {
        guard let target = effectiveAddress(operand) else { return }
        // Push the address of the last byte of the JSR instruction (PC - 1).
        pushWord(pc &- 1)
        pc = target
    }

    func rts() {
        pc = pullWord() &+ 1
    }

    func brk() {
        pc = pc &+ 1
        pushWord(pc)
        push((p.union([.breakFlag, .unused])).rawValue)
        p.insert(.interrupt)
        pc = bus.readWord(Vector.irq)
        // In the simplified core we treat BRK as a stop-the-program signal too.
        halt()
    }

    func rti() {
        p = StatusFlags(rawValue: pull()).union(.unused).subtracting(.breakFlag)
        pc = pullWord()
    }

    // MARK: Stack

    func php() { push(p.union([.breakFlag, .unused]).rawValue) }
    func plp() { p = StatusFlags(rawValue: pull()).union(.unused).subtracting(.breakFlag) }
    func pha() { push(a) }
    func pla() { a = pull(); p.updateZeroNegative(a) }
}
