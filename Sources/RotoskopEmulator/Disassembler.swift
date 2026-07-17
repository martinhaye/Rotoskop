//
//  Disassembler.swift
//  RotoskopEmulator
//
//  Turns bytes back into human-readable 6502 mnemonics. Used by the debugger
//  view and by tests. It shares the exact same opcode table as the CPU, so the
//  two can never drift apart.
//

import Foundation

/// A single disassembled line.
public struct DisassembledInstruction {
    public let address: UInt16
    public let bytes: [UInt8]
    public let mnemonic: String
    public let operandText: String

    /// e.g. `0800  A9 41     LDA #$41`
    public var text: String {
        let hexBytes = bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
        let padded = hexBytes.padding(toLength: 8, withPad: " ", startingAt: 0)
        let ops = operandText.isEmpty ? mnemonic : "\(mnemonic) \(operandText)"
        return String(format: "%04X  %@  %@", address, padded, ops)
    }
}

public struct Disassembler {
    private let table: [Instruction?]

    public init() {
        table = InstructionSet.buildTable()
    }

    /// Disassembles a single instruction at `address`, returning the decoded
    /// line and the address of the following instruction.
    public func decode(at address: UInt16, from bus: MemoryBus) -> (DisassembledInstruction, UInt16) {
        let opcode = bus.read(address)
        guard let instruction = table[Int(opcode)] else {
            let line = DisassembledInstruction(address: address, bytes: [opcode],
                                               mnemonic: "???",
                                               operandText: String(format: "$%02X", opcode))
            return (line, address &+ 1)
        }

        let length = instruction.mode.operandLength
        var bytes = [opcode]
        for i in 0..<length { bytes.append(bus.read(address &+ UInt16(i + 1))) }

        let operandText = format(mode: instruction.mode, bytes: bytes, at: address)
        let line = DisassembledInstruction(address: address, bytes: bytes,
                                           mnemonic: instruction.mnemonic,
                                           operandText: operandText)
        return (line, address &+ UInt16(1 + length))
    }

    /// Disassembles `count` instructions starting at `address`.
    public func disassemble(from address: UInt16, count: Int, bus: MemoryBus) -> [DisassembledInstruction] {
        var result: [DisassembledInstruction] = []
        var addr = address
        for _ in 0..<count {
            let (line, next) = decode(at: addr, from: bus)
            result.append(line)
            addr = next
        }
        return result
    }

    private func format(mode: AddressingMode, bytes: [UInt8], at address: UInt16) -> String {
        let one = bytes.count > 1 ? bytes[1] : 0
        let two = bytes.count > 2 ? bytes[2] : 0
        let word = UInt16(one) | (UInt16(two) << 8)
        switch mode {
        case .implied:          return ""
        case .accumulator:      return "A"
        case .immediate:        return String(format: "#$%02X", one)
        case .zeroPage:         return String(format: "$%02X", one)
        case .zeroPageX:        return String(format: "$%02X,X", one)
        case .zeroPageY:        return String(format: "$%02X,Y", one)
        case .absolute:         return String(format: "$%04X", word)
        case .absoluteX:        return String(format: "$%04X,X", word)
        case .absoluteY:        return String(format: "$%04X,Y", word)
        case .indirect:         return String(format: "($%04X)", word)
        case .indexedIndirect:  return String(format: "($%02X,X)", one)
        case .indirectIndexed:  return String(format: "($%02X),Y", one)
        case .relative:
            let target = UInt16(bitPattern: Int16(bitPattern: address &+ 2) &+ Int16(Int8(bitPattern: one)))
            return String(format: "$%04X", target)
        }
    }
}
