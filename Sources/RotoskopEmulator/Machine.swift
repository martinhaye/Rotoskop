//
//  Machine.swift
//  RotoskopEmulator
//
//  The top-level façade the app and tests interact with: it owns the memory
//  map and the CPU, loads programs, and drives execution with breakpoint and
//  cycle-budget support. Think of it as the "virtual Apple" object.
//

/// Reasons a `run` call stopped.
public enum StopReason: Equatable {
    case halted            // CPU hit BRK / an unimplemented opcode
    case breakpoint(UInt16)
    case reachedCycleBudget
    case reachedInstructionBudget
}

/// A simplified Apple II/III machine: CPU + memory map + debugging hooks.
public final class Machine {
    public let memory: AppleMemoryMap
    public let cpu: CPU6502
    public let disassembler: Disassembler

    /// Addresses that, when reached as the next instruction, stop execution.
    public var breakpoints: Set<UInt16> = []

    public init() {
        memory = AppleMemoryMap()
        cpu = CPU6502(bus: memory)
        disassembler = Disassembler()
    }

    // MARK: Program loading

    /// Loads `program` at `address`, points the reset vector at it, and resets
    /// the CPU so `PC` is ready to execute the first instruction.
    public func load(_ program: [UInt8], at address: UInt16 = MemoryRegion.programStart) {
        memory.ram.load(program, at: address)
        memory.setResetVector(address)
        cpu.reset()
    }

    // MARK: Execution

    /// Executes a single instruction (honouring breakpoints on the *next*
    /// instruction is the caller's job via `run`).
    @discardableResult
    public func step() -> Int {
        cpu.step()
    }

    /// Runs until the CPU halts, a breakpoint is hit, or a budget is exhausted.
    ///
    /// - Parameters:
    ///   - maxInstructions: safety cap on instructions executed.
    ///   - maxCycles: optional cap on simulated clock cycles.
    @discardableResult
    public func run(maxInstructions: Int = 1_000_000,
                    maxCycles: UInt64? = nil) -> StopReason {
        var executed = 0
        while executed < maxInstructions {
            if breakpoints.contains(cpu.pc) {
                return .breakpoint(cpu.pc)
            }
            cpu.step()
            executed += 1
            if cpu.halted { return .halted }
            if let budget = maxCycles, cpu.cycles >= budget {
                return .reachedCycleBudget
            }
        }
        return .reachedInstructionBudget
    }

    // MARK: Debug convenience

    /// A snapshot of the CPU registers, useful for tests and the debugger UI.
    public func registerSnapshot() -> RegisterSnapshot {
        RegisterSnapshot(a: cpu.a, x: cpu.x, y: cpu.y,
                         sp: cpu.sp, pc: cpu.pc,
                         status: cpu.p, cycles: cpu.cycles)
    }

    /// Renders the text screen to 24 lines.
    public func screenLines() -> [String] {
        memory.screenLines()
    }
}

/// An immutable snapshot of CPU state.
public struct RegisterSnapshot: Equatable {
    public let a: UInt8
    public let x: UInt8
    public let y: UInt8
    public let sp: UInt8
    public let pc: UInt16
    public let status: StatusFlags
    public let cycles: UInt64
}
