import Foundation

/// Flat 64KB address space for v1. Structure leaves room for future banking
/// (Apple II / III strategies diverge; banking itself is out of scope for v1).
public final class Memory {
    public static let size = 0x10000

    private var bytes: [UInt8]
    private var readHooks: [UInt16: () -> UInt8] = [:]
    private var writeHooks: [UInt16: (UInt8) -> Void] = [:]

    /// True once `$FFFE`/`$FFFF` have been written since the last `markVectorsUnset()`.
    /// Used for unhandled-BRK detection (fill value `$FF` does not count as set).
    public private(set) var irqVectorWritten = false

    public init() {
        bytes = [UInt8](repeating: 0xFF, count: Self.size)
    }

    /// Call on CPU reset so IRQ/BRK vector starts unset.
    public func markVectorsUnset() {
        irqVectorWritten = false
    }

    public func addReadHook(at addr: UInt16, hook: @escaping () -> UInt8) {
        readHooks[addr] = hook
    }

    public func addWriteHook(at addr: UInt16, hook: @escaping (UInt8) -> Void) {
        writeHooks[addr] = hook
    }

    public func read(_ addr: UInt16) -> UInt8 {
        if let hook = readHooks[addr] {
            return hook()
        }
        return bytes[Int(addr)]
    }

    public func write(_ addr: UInt16, _ value: UInt8) {
        if addr == 0xFFFE || addr == 0xFFFF {
            irqVectorWritten = true
        }
        if let hook = writeHooks[addr] {
            hook(value)
        } else {
            bytes[Int(addr)] = value
        }
    }

    public func readWord(_ addr: UInt16) -> UInt16 {
        let lo = UInt16(read(addr))
        let hi = UInt16(read(addr &+ 1))
        return lo | (hi << 8)
    }

    /// Zero-page word read; high byte wraps within page zero.
    public func readWordZP(_ addr: UInt8) -> UInt16 {
        let lo = UInt16(read(UInt16(addr)))
        let hi = UInt16(read(UInt16(addr &+ 1)))
        return lo | (hi << 8)
    }

    public func writeWord(_ addr: UInt16, _ value: UInt16) {
        write(addr, UInt8(value & 0xFF))
        write(addr &+ 1, UInt8((value >> 8) & 0xFF))
    }

    public func loadBinary(_ data: [UInt8], at start: UInt16) {
        for (i, byte) in data.enumerated() {
            write(start &+ UInt16(i), byte)
        }
    }

    public func loadBinary(_ data: Data, at start: UInt16) {
        loadBinary([UInt8](data), at: start)
    }

    public func setResetVector(_ addr: UInt16) {
        writeWord(0xFFFC, addr)
    }

    /// Inspection dump — bypasses read hooks so soft-switches are not triggered.
    public func dump(from start: UInt16, length: Int) -> [UInt8] {
        let s = Int(start)
        let end = min(s + length, bytes.count)
        guard s < end else { return [] }
        return Array(bytes[s..<end])
    }

    /// Raw byte for dump/screen without hooks.
    public func peek(_ addr: UInt16) -> UInt8 {
        bytes[Int(addr)]
    }
}
