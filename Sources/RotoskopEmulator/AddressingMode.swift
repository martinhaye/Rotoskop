//
//  AddressingMode.swift
//  RotoskopEmulator
//
//  The 6502 addressing modes and the machinery to resolve an operand into an
//  effective address. Instruction handlers stay tiny because all of the
//  address arithmetic lives here.
//

/// The 13 addressing modes of the NMOS 6502.
public enum AddressingMode: String, Sendable, CaseIterable {
    case implied
    case accumulator
    case immediate
    case zeroPage
    case zeroPageX
    case zeroPageY
    case absolute
    case absoluteX
    case absoluteY
    case indirect            // JMP ($nnnn)
    case indexedIndirect     // ($nn,X)
    case indirectIndexed     // ($nn),Y
    case relative            // branches

    /// Number of operand bytes that follow the opcode for this mode.
    public var operandLength: Int {
        switch self {
        case .implied, .accumulator:
            return 0
        case .immediate, .zeroPage, .zeroPageX, .zeroPageY,
             .indexedIndirect, .indirectIndexed, .relative:
            return 1
        case .absolute, .absoluteX, .absoluteY, .indirect:
            return 2
        }
    }
}

/// The resolved target of an instruction's operand.
///
/// - `implied`: no operand (or the accumulator is the implicit target).
/// - `value`: an immediate literal.
/// - `address`: an effective memory address, plus whether resolving it crossed
///   a page boundary (some instructions take an extra cycle when it does).
public enum Operand {
    case implied
    case value(UInt8)
    case address(UInt16, pageCrossed: Bool)
}
