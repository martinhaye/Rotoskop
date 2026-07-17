//
//  TextScreen.swift
//  RotoskopEmulator
//
//  Decodes the Apple II 40×24 text screen out of memory. The Apple II text
//  buffer is famously non-linear: the 24 rows are interleaved in three groups
//  of eight. This type hides that layout so the UI (and tests) can ask for
//  "row 5" and get back plain characters.
//

/// Decodes the 40×24 text page into characters.
///
/// The screen occupies $0400–$07FF (text page 1). Each visible row starts at:
/// `base + (row % 8) * 0x80 + (row / 8) * 0x28`.
public struct TextScreen {
    public static let columns = 40
    public static let rows = 24

    /// Base address of the text page (page 1 by default).
    public let base: UInt16

    public init(base: UInt16 = 0x0400) {
        self.base = base
    }

    /// The starting address of a given screen row (0..<24).
    public func rowAddress(_ row: Int) -> UInt16 {
        precondition((0..<TextScreen.rows).contains(row), "row out of range")
        let offset = (row % 8) * 0x80 + (row / 8) * 0x28
        return base &+ UInt16(offset)
    }

    /// Decodes a single screen cell to a displayable ASCII `Character`.
    ///
    /// Apple II character memory uses the high bit(s) to select normal / inverse
    /// / flashing text. In this simplified core we mask to 7 bits and map the
    /// primary uppercase range to ASCII; unprintable values become a space.
    public func character(at byte: UInt8) -> Character {
        let code = byte & 0x7F
        switch code {
        case 0x00...0x1F: return Character(UnicodeScalar(code + 0x40)) // @A..._ (uppercase)
        case 0x20...0x3F: return Character(UnicodeScalar(code))        // space, digits, punctuation
        case 0x40...0x5F: return Character(UnicodeScalar(code))        // @A.._ again
        default:          return Character(UnicodeScalar(code))        // lowercase / extended
        }
    }

    /// Reads one row of the screen from `bus` as a `String`.
    public func row(_ row: Int, from bus: MemoryBus) -> String {
        let start = rowAddress(row)
        var chars = ""
        chars.reserveCapacity(TextScreen.columns)
        for col in 0..<TextScreen.columns {
            chars.append(character(at: bus.read(start &+ UInt16(col))))
        }
        return chars
    }

    /// Reads the whole screen as an array of 24 row strings.
    public func lines(from bus: MemoryBus) -> [String] {
        (0..<TextScreen.rows).map { row($0, from: bus) }
    }

    /// Reads the whole screen as a single newline-joined string.
    public func render(from bus: MemoryBus) -> String {
        lines(from: bus).joined(separator: "\n")
    }
}
