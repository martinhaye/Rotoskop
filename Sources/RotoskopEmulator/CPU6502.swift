//
//  CPU6502.swift
//  RotoskopEmulator
//
//  The NMOS 6502 core: register file, the fetch/decode/execute loop, operand
//  resolution, and the stack/interrupt plumbing that individual instruction
//  handlers rely on.
//
//  NOTE ON PORTING: instruction *behaviour* lives in `InstructionSet.swift`,
//  which builds a 256-entry dispatch table. Porting the existing Python core is
//  primarily a matter of filling in that table; this file provides the shared
//  machinery (addressing, flags, stack, cycle accounting) those handlers use.
//

/// Standard 6502 vector locations.
public enum Vector {
    public static let nmi: UInt16   = 0xFFFA
    public static let reset: UInt16 = 0xFFFC
    public static let irq: UInt16   = 0xFFFE   // also used by BRK
}

/// A cycle-counting NMOS 6502 CPU.
public final class CPU6502 {
    // MARK: Registers
    public var a: UInt8 = 0            // accumulator
    public var x: UInt8 = 0            // index X
    public var y: UInt8 = 0            // index Y
    public var sp: UInt8 = 0xFD        // stack pointer (offset into page 1)
    public var pc: UInt16 = 0          // program counter
    public var p: StatusFlags = [.interrupt, .unused]  // status register

    /// Total elapsed clock cycles since construction / reset.
    public private(set) var cycles: UInt64 = 0

    /// Set when a `BRK`/halt condition is reached, so callers running a batch of
    /// instructions know to stop.
    public private(set) var halted: Bool = false

    /// The memory the CPU is wired to.
    public let bus: MemoryBus

    /// The opcode dispatch table, indexed by opcode byte.
    let table: [Instruction?]

    public init(bus: MemoryBus) {
        self.bus = bus
        self.table = InstructionSet.buildTable()
    }

    // MARK: - Reset

    /// Performs a power-on / reset sequence: loads `PC` from the reset vector
    /// and puts the status/stack registers in their canonical post-reset state.
    public func reset() {
        a = 0; x = 0; y = 0
        sp = 0xFD
        p = [.interrupt, .unused]
        pc = bus.readWord(Vector.reset)
        cycles = 0
        halted = false
    }

    /// Forces the program counter to `address` (handy for tests that load a
    /// program at a known location and want to start executing there).
    public func jump(to address: UInt16) {
        pc = address
        halted = false
    }

    // MARK: - Fetch/decode/execute

    /// Executes a single instruction and returns the number of clock cycles it
    /// consumed. Returns 0 (and sets `halted`) if the opcode is not yet
    /// implemented in the dispatch table.
    @discardableResult
    public func step() -> Int {
        let opcode = fetchByte()
        guard let instruction = table[Int(opcode)] else {
            // Unimplemented opcode: back up PC so it can be inspected, halt.
            pc = pc &- 1
            halted = true
            return 0
        }

        let operand = resolve(instruction.mode)
        var consumed = instruction.baseCycles
        if instruction.addsCycleOnPageCross, case let .address(_, crossed) = operand, crossed {
            consumed += 1
        }
        instruction.execute(self, operand)
        cycles &+= UInt64(consumed)
        return consumed
    }

    /// Reads the byte at `PC` and advances the program counter.
    @inline(__always)
    func fetchByte() -> UInt8 {
        let value = bus.read(pc)
        pc = pc &+ 1
        return value
    }

    /// Reads a little-endian word at `PC` and advances the program counter by 2.
    @inline(__always)
    func fetchWord() -> UInt16 {
        let lo = UInt16(fetchByte())
        let hi = UInt16(fetchByte())
        return (hi << 8) | lo
    }

    // MARK: - Operand resolution

    /// Consumes the operand bytes for `mode` and produces a resolved `Operand`.
    func resolve(_ mode: AddressingMode) -> Operand {
        switch mode {
        case .implied, .accumulator:
            return .implied

        case .immediate:
            return .value(fetchByte())

        case .zeroPage:
            return .address(UInt16(fetchByte()), pageCrossed: false)

        case .zeroPageX:
            let base = fetchByte()
            return .address(UInt16(base &+ x), pageCrossed: false)

        case .zeroPageY:
            let base = fetchByte()
            return .address(UInt16(base &+ y), pageCrossed: false)

        case .absolute:
            return .address(fetchWord(), pageCrossed: false)

        case .absoluteX:
            let base = fetchWord()
            let addr = base &+ UInt16(x)
            return .address(addr, pageCrossed: pageCrossed(base, addr))

        case .absoluteY:
            let base = fetchWord()
            let addr = base &+ UInt16(y)
            return .address(addr, pageCrossed: pageCrossed(base, addr))

        case .indirect:
            let pointer = fetchWord()
            return .address(bus.readWordPageWrapped(pointer), pageCrossed: false)

        case .indexedIndirect: // ($nn,X)
            let zp = fetchByte() &+ x
            let addr = bus.readWordPageWrapped(UInt16(zp))
            return .address(addr, pageCrossed: false)

        case .indirectIndexed: // ($nn),Y
            let zp = fetchByte()
            let base = bus.readWordPageWrapped(UInt16(zp))
            let addr = base &+ UInt16(y)
            return .address(addr, pageCrossed: pageCrossed(base, addr))

        case .relative:
            // Operand is a signed 8-bit offset relative to the address *after*
            // the branch instruction. We resolve it to the absolute target.
            let offset = Int8(bitPattern: fetchByte())
            let target = UInt16(bitPattern: Int16(bitPattern: pc) &+ Int16(offset))
            return .address(target, pageCrossed: pageCrossed(pc, target))
        }
    }

    @inline(__always)
    private func pageCrossed(_ a: UInt16, _ b: UInt16) -> Bool {
        (a & 0xFF00) != (b & 0xFF00)
    }

    // MARK: - Operand helpers used by instruction handlers

    /// Reads the value an operand refers to (immediate literal or memory byte).
    @inline(__always)
    func loadOperand(_ operand: Operand) -> UInt8 {
        switch operand {
        case .value(let v):          return v
        case .address(let addr, _):  return bus.read(addr)
        case .implied:               return a  // accumulator-mode read
        }
    }

    /// The effective address of an operand, or nil for immediate/implied.
    @inline(__always)
    func effectiveAddress(_ operand: Operand) -> UInt16? {
        if case .address(let addr, _) = operand { return addr }
        return nil
    }

    // MARK: - Stack (page 1: $0100–$01FF)

    @inline(__always)
    func push(_ value: UInt8) {
        bus.write(0x0100 | UInt16(sp), value)
        sp = sp &- 1
    }

    @inline(__always)
    func pull() -> UInt8 {
        sp = sp &+ 1
        return bus.read(0x0100 | UInt16(sp))
    }

    @inline(__always)
    func pushWord(_ value: UInt16) {
        push(UInt8(value >> 8))
        push(UInt8(value & 0xFF))
    }

    @inline(__always)
    func pullWord() -> UInt16 {
        let lo = UInt16(pull())
        let hi = UInt16(pull())
        return (hi << 8) | lo
    }

    /// Marks the CPU as halted (used by `BRK` in the simplified core).
    func halt() { halted = true }
}
