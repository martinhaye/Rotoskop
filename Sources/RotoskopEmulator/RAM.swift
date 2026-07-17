//
//  RAM.swift
//  RotoskopEmulator
//
//  A trivial, flat 64K RAM. Useful on its own for CPU unit tests where we do
//  not care about the Apple II/III memory map, and as the backing store for
//  richer memory maps.
//

/// A flat 64 KiB read/write memory.
public final class RAM: MemoryBus {
    /// The raw backing bytes. Exposed so tests and debuggers can peek/poke
    /// without going through the (side-effecting) bus interface.
    public private(set) var bytes: [UInt8]

    public init() {
        bytes = [UInt8](repeating: 0, count: 0x1_0000)
    }

    /// Resets all memory to `value` (0 by default).
    public func clear(to value: UInt8 = 0) {
        for i in bytes.indices { bytes[i] = value }
    }

    /// Copies `program` into memory starting at `address`.
    public func load(_ program: [UInt8], at address: UInt16) {
        var addr = Int(address)
        for byte in program {
            guard addr < bytes.count else { break }
            bytes[addr] = byte
            addr += 1
        }
    }

    public func read(_ address: UInt16) -> UInt8 {
        bytes[Int(address)]
    }

    public func write(_ address: UInt16, _ value: UInt8) {
        bytes[Int(address)] = value
    }
}
