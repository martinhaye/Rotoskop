import Foundation

#if canImport(UIKit)
import UIKit
#endif

/// Simple assembly syntax highlighting (DESIGN §3.4).
public enum AssemblyHighlighter {
    public enum TokenKind: Equatable, Sendable {
        case comment
        case directive
        case opcode
        case number
        case string
        case label
        case plain
    }

    public struct Token: Equatable, Sendable {
        public var kind: TokenKind
        public var range: Range<String.Index>
    }

    private static let opcodes: Set<String> = [
        "adc", "and", "asl", "bcc", "bcs", "beq", "bit", "bmi", "bne", "bpl", "brk", "bvc", "bvs",
        "clc", "cld", "cli", "clv", "cmp", "cpx", "cpy", "dec", "dex", "dey", "eor", "inc", "inx",
        "iny", "jmp", "jsr", "lda", "ldx", "ldy", "lsr", "nop", "ora", "pha", "php", "pla", "plp",
        "rol", "ror", "rti", "rts", "sbc", "sec", "sed", "sei", "sta", "stx", "sty", "tax", "tay",
        "tsx", "txa", "txs", "tya",
        // runix / common macros often look like opcodes in listings
        "ldax", "stax",
    ]

    public static func tokens(in text: String) -> [Token] {
        var result: [Token] = []
        var lineStart = text.startIndex
        while lineStart < text.endIndex {
            let lineEnd = text[lineStart...].firstIndex(of: "\n").map { text.index(after: $0) } ?? text.endIndex
            let line = lineStart..<lineEnd
            result.append(contentsOf: tokensInLine(text, line: line))
            lineStart = lineEnd
        }
        return result
    }

    private static func tokensInLine(_ text: String, line: Range<String.Index>) -> [Token] {
        var tokens: [Token] = []
        var i = line.lowerBound
        let end = line.upperBound

        // Trim trailing newline from scanning range for content.
        var contentEnd = end
        if contentEnd > i, text[text.index(before: contentEnd)] == "\n" {
            contentEnd = text.index(before: contentEnd)
        }

        var firstNonWS = true
        while i < contentEnd {
            let ch = text[i]
            if ch == " " || ch == "\t" {
                i = text.index(after: i)
                continue
            }
            if ch == ";" {
                tokens.append(Token(kind: .comment, range: i..<contentEnd))
                break
            }
            if ch == "\"" {
                let start = i
                i = text.index(after: i)
                while i < contentEnd {
                    if text[i] == "\\" {
                        i = text.index(after: i)
                        if i < contentEnd { i = text.index(after: i) }
                        continue
                    }
                    if text[i] == "\"" {
                        i = text.index(after: i)
                        break
                    }
                    i = text.index(after: i)
                }
                tokens.append(Token(kind: .string, range: start..<i))
                firstNonWS = false
                continue
            }
            if ch == "." {
                let start = i
                i = text.index(after: i)
                while i < contentEnd, isIdentChar(text[i]) {
                    i = text.index(after: i)
                }
                tokens.append(Token(kind: .directive, range: start..<i))
                firstNonWS = false
                continue
            }
            if ch == "$" || ch == "%" || ch.isNumber {
                let start = i
                i = text.index(after: i)
                while i < contentEnd {
                    let c = text[i]
                    if c.isHexDigit || c == "_" { i = text.index(after: i); continue }
                    break
                }
                tokens.append(Token(kind: .number, range: start..<i))
                firstNonWS = false
                continue
            }
            if isIdentStart(ch) {
                let start = i
                i = text.index(after: i)
                while i < contentEnd, isIdentChar(text[i]) {
                    i = text.index(after: i)
                }
                var kind: TokenKind = .plain
                let word = String(text[start..<i]).lowercased()
                if i < contentEnd, text[i] == ":" {
                    kind = .label
                    i = text.index(after: i)
                } else if firstNonWS {
                    // bare label at column 0 without colon is uncommon; treat as label-ish only with :
                    kind = opcodes.contains(word) ? .opcode : .plain
                } else if opcodes.contains(word) {
                    kind = .opcode
                }
                tokens.append(Token(kind: kind, range: start..<i))
                firstNonWS = false
                continue
            }
            i = text.index(after: i)
            firstNonWS = false
        }
        return tokens
    }

    private static func isIdentStart(_ ch: Character) -> Bool {
        ch.isLetter || ch == "_" || ch == "@"
    }

    private static func isIdentChar(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber || ch == "_" || ch == "@"
    }

    #if canImport(UIKit)
    public static func attributedString(
        for text: String,
        font: UIFont,
        plainColor: UIColor = .label,
        isAssembly: Bool
    ) -> NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.lineBreakMode = .byClipping
        // Standard tab stops every 8 character widths (monospace coding font).
        let charWidth = (" " as NSString).size(withAttributes: [.font: font]).width
        paragraph.tabStops = []
        paragraph.defaultTabInterval = 8 * charWidth

        let base: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: plainColor,
            .paragraphStyle: paragraph,
        ]
        let result = NSMutableAttributedString(string: text, attributes: base)
        guard isAssembly else { return result }

        let colors: [TokenKind: UIColor] = [
            .comment: .secondaryLabel,
            .directive: UIColor.systemPurple,
            .opcode: UIColor.systemBlue,
            .number: UIColor.systemOrange,
            .string: UIColor.systemGreen,
            .label: UIColor.systemTeal,
            .plain: plainColor,
        ]

        for token in tokens(in: text) {
            guard token.kind != .plain else { continue }
            let nsRange = NSRange(token.range, in: text)
            guard nsRange.location != NSNotFound else { continue }
            result.addAttribute(.foregroundColor, value: colors[token.kind] ?? plainColor, range: nsRange)
        }
        return result
    }
    #endif
}
