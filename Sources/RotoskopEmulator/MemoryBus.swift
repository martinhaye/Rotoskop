//
//  MemoryBus.swift
//  RotoskopEmulator
//
//  The abstraction the CPU uses to talk to the rest of the machine. Everything
//  the CPU can address — RAM, ROM, the text screen, and (later) soft-switches /
//  memory-mapped I/O — sits behind this protocol. Keeping the CPU decoupled
//  from any concrete memory layout is what makes the core easy to test.
//

/// A 16-bit address space the CPU can read from and write to.
///
/// Implementations are free to interpret addresses however they like (plain
/// RAM, banked memory, memory-mapped I/O, etc.). The CPU never assumes anything
/// beyond "give me a byte at this address" / "store this byte at this address".
public protocol MemoryBus: AnyObject {
    /// Reads the byte at `address`.
    func read(_ address: UInt16) -> UInt8
    /// Writes `value` to `address`.
    func write(_ address: UInt16, _ value: UInt8)
}

public extension MemoryBus {
    /// Reads a little-endian 16-bit word at `address`.
    @inline(__always)
    func readWord(_ address: UInt16) -> UInt16 {
        let lo = UInt16(read(address))
        let hi = UInt16(read(address &+ 1))
        return (hi << 8) | lo
    }

    /// Reads a little-endian 16-bit word, reproducing the 6502 "page wrap" bug
    /// where the high byte is fetched from the start of the same page rather
    /// than crossing into the next one. Used by indirect `JMP` and the
    /// zero-page indexed-indirect addressing modes.
    @inline(__always)
    func readWordPageWrapped(_ address: UInt16) -> UInt16 {
        let lo = UInt16(read(address))
        let hiAddr = (address & 0xFF00) | UInt16((address &+ 1) & 0x00FF)
        let hi = UInt16(read(hiAddr))
        return (hi << 8) | lo
    }
}
