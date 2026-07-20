import Foundation

// MARK: - Text screen

public enum TextScreen {
    public static let screenBase: UInt16 = 0x0400
    public static let cols = 40
    public static let rows = 24

    public struct Cell: Equatable, Sendable {
        public var character: Character
        public var inverse: Bool
    }

    public static func lineAddress(_ line: Int) -> UInt16 {
        let group = line / 8
        let rowInGroup = line % 8
        return UInt16(0x400 + rowInGroup * 0x80 + group * 0x28)
    }

    /// Decode one Apple II text-screen byte.
    /// High bit set = normal; clear = inverse/flash (Runix cursor toggles via `eor #$80`).
    public static func decode(_ byte: UInt8) -> Cell {
        if byte == 0xFF {
            return Cell(character: " ", inverse: false)
        }
        let inverse = (byte & 0x80) == 0
        var ch = byte & 0x7F
        // Inverse/flash $00–$1F are @–_ glyphs (e.g. $01 = inverse 'A').
        if inverse && ch < 0x20 {
            ch |= 0x40
        }
        if ch < 0x20 || ch > 0x7E {
            return Cell(character: " ", inverse: inverse)
        }
        return Cell(character: Character(UnicodeScalar(ch)), inverse: inverse)
    }

    /// Per-row cells with trailing normal spaces trimmed (inverse spaces kept for cursor).
    /// Keeps all 24 rows so the emulator viewport stays a stable 40×24 grid.
    public static func dumpCells(_ memory: Memory, trimEmptyRows: Bool = false) -> [[Cell]] {
        var lines: [[Cell]] = []
        for row in 0..<rows {
            let base = lineAddress(row)
            var cells: [Cell] = []
            for col in 0..<cols {
                cells.append(decode(memory.peek(base &+ UInt16(col))))
            }
            while let last = cells.last, last.character == " ", !last.inverse {
                cells.removeLast()
            }
            lines.append(cells)
        }
        if trimEmptyRows {
            while let first = lines.first, first.isEmpty { lines.removeFirst() }
            while let last = lines.last, last.isEmpty { lines.removeLast() }
        }
        return lines
    }

    /// Decode `$400–$7FF` Apple II text layout to a trimmed string (uses peek / dump, not hooks).
    /// Inverse/flash spaces become `█` so a cursor (hi-bit cleared) stays visible after trim.
    public static func dump(_ memory: Memory) -> String {
        dumpCellsToString(dumpCells(memory, trimEmptyRows: true))
    }

    public static func dumpCellsToString(_ lines: [[Cell]]) -> String {
        lines.map { line in
            String(line.map { cell in
                cell.inverse && cell.character == " " ? "█" : cell.character
            })
        }.joined(separator: "\n")
    }
}

// MARK: - Keyboard

public final class Keyboard {
    public static let kbdData: UInt16 = 0xC000
    public static let kbdStrobe: UInt16 = 0xC010

    private var buffer: [UInt8]
    private var index = 0
    private let lock = NSLock()

    public init(inputStrings: [String]) {
        buffer = Self.parseInput(inputStrings)
    }

    /// Push a raw key for interactive (app) mode. Value is lo-bit ASCII; hi-bit set on read.
    public func injectKey(_ key: UInt8) {
        lock.lock()
        defer { lock.unlock() }
        buffer.append(key)
    }

    public var hasInput: Bool {
        lock.lock()
        defer { lock.unlock() }
        return index < buffer.count
    }

    public func readKbd() -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        if index < buffer.count {
            return buffer[index] | 0x80
        }
        return 0x00
    }

    @discardableResult
    public func clearStrobe() -> UInt8 {
        lock.lock()
        defer { lock.unlock() }
        let result: UInt8
        if index < buffer.count {
            result = buffer[index] | 0x80
        } else {
            result = 0x00
        }
        if index < buffer.count {
            index += 1
        }
        return result
    }

    public static func parseInput(_ strings: [String]) -> [UInt8] {
        var result: [UInt8] = []
        for s in strings {
            var i = s.startIndex
            while i < s.endIndex {
                if s[i] == "\\" {
                    let next = s.index(after: i)
                    guard next < s.endIndex else {
                        result.append(UInt8(ascii: "\\"))
                        break
                    }
                    switch s[next] {
                    case "n", "r":
                        result.append(0x0D)
                        i = s.index(after: next)
                    case "t":
                        result.append(0x09)
                        i = s.index(after: next)
                    case "\\":
                        result.append(UInt8(ascii: "\\"))
                        i = s.index(after: next)
                    case "0":
                        result.append(0x00)
                        i = s.index(after: next)
                    case "e":
                        result.append(0x1B)
                        i = s.index(after: next)
                    case "x":
                        let h1 = s.index(after: next)
                        let h2 = s.index(h1, offsetBy: 1, limitedBy: s.endIndex) ?? s.endIndex
                        if h2 < s.endIndex || (h1 < s.endIndex && s.distance(from: h1, to: s.endIndex) >= 2) {
                            let end = s.index(h1, offsetBy: 2, limitedBy: s.endIndex) ?? s.endIndex
                            let hex = String(s[h1..<end])
                            if let v = UInt8(hex, radix: 16) {
                                result.append(v)
                                i = end
                            } else {
                                result.append(UInt8(ascii: "\\"))
                                i = next
                            }
                        } else {
                            result.append(UInt8(ascii: "\\"))
                            i = next
                        }
                    default:
                        result.append(UInt8(ascii: "\\"))
                        i = next
                    }
                } else {
                    let scalar = s[i].unicodeScalars.first!.value
                    if scalar == 0x0A || scalar == 0x0D {
                        // YAML / real newlines → Apple II CR (same as \n escape)
                        result.append(0x0D)
                    } else {
                        result.append(UInt8(truncatingIfNeeded: scalar))
                    }
                    i = s.index(after: i)
                }
            }
        }
        return result
    }
}

// MARK: - Hard drive (.2mg, slot 2)

public final class HardDrive {
    public static let blockSize = 512
    public static let headerSize = 64
    public static let romBase: UInt16 = 0xC200
    public static let romSize = 0x100
    public static let entryPoint: UInt16 = 0xC20A

    public static let paramCmd = 0x42
    public static let paramUnit = 0x43
    public static let paramBufLo = 0x44
    public static let paramBufHi = 0x45
    public static let paramBlkLo = 0x46
    public static let paramBlkHi = 0x47
    public static let cmdRead = 1
    public static let cmdWrite = 2

    /// Private working copy — never mutates the build artifact on disk.
    private var image: Data

    public init(imagePath: String) throws {
        let url = URL(fileURLWithPath: imagePath)
        let original = try Data(contentsOf: url)
        // Full private copy at run start (DESIGN §6.4).
        image = Data(original)
    }

    /// In-memory image for tests.
    public init(imageData: Data) {
        image = Data(imageData)
    }

    public func romBytes() -> [UInt8] {
        var rom = [UInt8](repeating: 0, count: Self.romSize)
        rom[0x01] = 0x20
        rom[0x03] = 0x00
        rom[0x05] = 0x03
        rom[0x07] = 0x00
        rom[0xFF] = 0x0A
        rom[0x0A] = 0x60 // RTS (PC hook handles the call)
        return rom
    }

    public func readBlock(_ blockNum: Int) throws -> [UInt8] {
        let offset = Self.headerSize + blockNum * Self.blockSize
        guard offset + Self.blockSize <= image.count else {
            throw DiskError.outOfRange(blockNum)
        }
        return [UInt8](image[offset..<(offset + Self.blockSize)])
    }

    public func writeBlock(_ blockNum: Int, data: [UInt8]) throws {
        guard data.count == Self.blockSize else {
            throw DiskError.badBlockSize(data.count)
        }
        let offset = Self.headerSize + blockNum * Self.blockSize
        guard offset + Self.blockSize <= image.count else {
            throw DiskError.outOfRange(blockNum)
        }
        image.replaceSubrange(offset..<(offset + Self.blockSize), with: data)
    }

    /// Handle ProDOS block device call. Returns `(A, carry)`.
    public func handleBlockCall(memory: Memory) throws -> (UInt8, Bool) {
        let cmd = Int(memory.read(UInt16(Self.paramCmd)))
        let unit = memory.read(UInt16(Self.paramUnit))
        let bufAddr = UInt16(memory.read(UInt16(Self.paramBufLo)))
            | (UInt16(memory.read(UInt16(Self.paramBufHi))) << 8)
        let blockNum = Int(memory.read(UInt16(Self.paramBlkLo)))
            | (Int(memory.read(UInt16(Self.paramBlkHi))) << 8)

        guard unit == 0x20 else {
            throw DiskError.invalidUnit(unit)
        }

        switch cmd {
        case Self.cmdRead:
            let data = try readBlock(blockNum)
            for (i, byte) in data.enumerated() {
                memory.write(bufAddr &+ UInt16(i), byte)
            }
            return (0, false)
        case Self.cmdWrite:
            var data = [UInt8](repeating: 0, count: Self.blockSize)
            for i in 0..<Self.blockSize {
                data[i] = memory.read(bufAddr &+ UInt16(i))
            }
            try writeBlock(blockNum, data: data)
            return (0, false)
        default:
            throw DiskError.invalidCommand(cmd)
        }
    }
}

public enum DiskError: Error, CustomStringConvertible {
    case outOfRange(Int)
    case badBlockSize(Int)
    case invalidUnit(UInt8)
    case invalidCommand(Int)

    public var description: String {
        switch self {
        case .outOfRange(let b): return "Block \(b) out of range"
        case .badBlockSize(let n): return "Block must be \(HardDrive.blockSize) bytes (got \(n))"
        case .invalidUnit(let u): return String(format: "Invalid unit number: $%02X (expected $20)", u)
        case .invalidCommand(let c): return String(format: "Invalid command: $%02X", c)
        }
    }
}
