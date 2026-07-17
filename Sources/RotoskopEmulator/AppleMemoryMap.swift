//
//  AppleMemoryMap.swift
//  RotoskopEmulator
//
//  A deliberately simplified Apple II/III-flavoured memory map. For now it is a
//  flat 64K space with named regions so the rest of the system (and the UI) can
//  talk about "the text screen" or "the zero page" symbolically. Soft-switches
//  and banked memory can be layered in here later without touching the CPU.
//

/// Named, well-known regions of the address space.
public enum MemoryRegion {
    public static let zeroPage: ClosedRange<UInt16>   = 0x0000...0x00FF
    public static let stack: ClosedRange<UInt16>      = 0x0100...0x01FF
    public static let textPage1: ClosedRange<UInt16>  = 0x0400...0x07FF
    public static let textPage2: ClosedRange<UInt16>  = 0x0800...0x0BFF
    /// Where user programs are conventionally loaded in this simplified machine.
    public static let programStart: UInt16 = 0x0800
}

/// The simplified Apple II/III memory map.
///
/// This is intentionally thin today — a flat RAM with helpers. It exists as a
/// distinct type (rather than using `RAM` directly) so that memory-mapped I/O,
/// ROM overlays, and soft-switches have a natural home as the emulator grows.
public final class AppleMemoryMap: MemoryBus {
    public let ram: RAM
    public let textScreen: TextScreen

    public init() {
        ram = RAM()
        textScreen = TextScreen(base: MemoryRegion.textPage1.lowerBound)
    }

    public func read(_ address: UInt16) -> UInt8 {
        ram.read(address)
    }

    public func write(_ address: UInt16, _ value: UInt8) {
        ram.write(address, value)
    }

    /// Convenience for wiring up the reset vector before running a program.
    public func setResetVector(_ address: UInt16) {
        ram.write(Vector.reset, UInt8(address & 0xFF))
        ram.write(Vector.reset &+ 1, UInt8(address >> 8))
    }

    /// The current text screen contents as 24 strings.
    public func screenLines() -> [String] {
        textScreen.lines(from: self)
    }
}
