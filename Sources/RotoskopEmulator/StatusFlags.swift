//
//  StatusFlags.swift
//  RotoskopEmulator
//
//  The 6502 processor status register (P) modelled as an OptionSet.
//

/// The 6502 processor status register (`P`).
///
/// Bit layout (bit 0 = least significant):
/// ```
/// 7  6  5  4  3  2  1  0
/// N  V  -  B  D  I  Z  C
/// ```
public struct StatusFlags: OptionSet, Sendable, Hashable {
    public var rawValue: UInt8
    public init(rawValue: UInt8) { self.rawValue = rawValue }

    /// Carry.
    public static let carry     = StatusFlags(rawValue: 1 << 0)
    /// Zero.
    public static let zero      = StatusFlags(rawValue: 1 << 1)
    /// Interrupt disable.
    public static let interrupt = StatusFlags(rawValue: 1 << 2)
    /// Decimal mode.
    public static let decimal   = StatusFlags(rawValue: 1 << 3)
    /// Break command (only meaningful in the value pushed to the stack).
    public static let breakFlag = StatusFlags(rawValue: 1 << 4)
    /// Unused bit — physically always reads as 1 on a real 6502.
    public static let unused    = StatusFlags(rawValue: 1 << 5)
    /// Overflow.
    public static let overflow  = StatusFlags(rawValue: 1 << 6)
    /// Negative.
    public static let negative  = StatusFlags(rawValue: 1 << 7)

    /// Convenience helper to set or clear a flag from a `Bool` condition.
    @inline(__always)
    public mutating func set(_ flag: StatusFlags, _ on: Bool) {
        if on { insert(flag) } else { remove(flag) }
    }

    /// Updates the Zero and Negative flags from an 8-bit result, the most
    /// common side effect of arithmetic and load instructions.
    @inline(__always)
    public mutating func updateZeroNegative(_ value: UInt8) {
        set(.zero, value == 0)
        set(.negative, value & 0x80 != 0)
    }
}
