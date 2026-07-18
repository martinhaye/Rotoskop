import Foundation

enum TokenKind: Equatable {
    case ident(String)          // lowercased for opcodes; preserve original in text
    case number(Int)            // already parsed value
    case string(String)         // decoded string contents
    case char(UInt8)            // character constant value
    case hash                   // #
    case lt                     // <
    case gt                     // >
    case amp                    // &
    case colon                  // :
    case colonColon             // ::
    case comma
    case lParen
    case rParen
    case lBrace                 // {
    case rBrace                 // }
    case plus
    case minus
    case star
    case slash
    case pipe                   // |
    case caret                  // ^
    case tilde                  // ~
    case equal                  // = (equate or equality)
    case notEqual               // <>
    case le                     // <=
    case ge                     // >=
    case at                     // @ (cheap local prefix kept with ident usually)
    case dotIdent(String)       // .byte, .match, etc. (lowercased name without dot)
    case eol
    case eof
}

struct Token: Equatable {
    var kind: TokenKind
    var text: String            // original spelling
    var location: SourceLocation
}

struct Lexer {
    let source: String
    let file: String
    var stringEscapes: Bool

    private var chars: [Character]
    private var index = 0
    private var line = 1
    private var column = 1

    init(source: String, file: String, stringEscapes: Bool = false) {
        self.source = source
        self.file = file
        self.stringEscapes = stringEscapes
        self.chars = Array(source)
    }

    mutating func next() -> Token {
        skipWhitespaceAndComments()
        let loc = location()
        guard index < chars.count else {
            return Token(kind: .eof, text: "", location: loc)
        }

        let c = chars[index]

        if c == "\n" {
            advance()
            return Token(kind: .eol, text: "\n", location: loc)
        }

        // Dot-directive / pseudo
        if c == "." {
            advance()
            let name = readIdentChars()
            return Token(kind: .dotIdent(name.lowercased()), text: "." + name, location: loc)
        }

        // String
        if c == "\"" {
            return readString(loc)
        }

        // Char constant
        if c == "'" {
            return readChar(loc)
        }

        // Number: $hex, %bin, decimal
        if c == "$" {
            advance()
            let digits = readWhile { $0.isHexDigit }
            let v = Int(digits, radix: 16) ?? 0
            return Token(kind: .number(v), text: "$" + digits, location: loc)
        }
        if c == "%" && peekIsDigitOrBin() {
            advance()
            let digits = readWhile { $0 == "0" || $0 == "1" }
            let v = Int(digits, radix: 2) ?? 0
            return Token(kind: .number(v), text: "%" + digits, location: loc)
        }
        if c.isNumber {
            let digits = readWhile { $0.isNumber }
            let v = Int(digits) ?? 0
            return Token(kind: .number(v), text: digits, location: loc)
        }

        // Ident or @cheap or :unnamed
        if c == "@" {
            advance()
            let name = readIdentChars()
            return Token(kind: .ident("@" + name), text: "@" + name, location: loc)
        }

        if c == ":" {
            advance()
            if index < chars.count && chars[index] == ":" {
                advance()
                return Token(kind: .colonColon, text: "::", location: loc)
            }
            return Token(kind: .colon, text: ":", location: loc)
        }

        if c.isIdentStart {
            let name = readIdentChars()
            return Token(kind: .ident(name), text: name, location: loc)
        }

        // Single/double char punct
        advance()
        switch c {
        case "#": return Token(kind: .hash, text: "#", location: loc)
        case "<":
            if index < chars.count && chars[index] == ">" {
                advance()
                return Token(kind: .notEqual, text: "<>", location: loc)
            }
            if index < chars.count && chars[index] == "=" {
                advance()
                return Token(kind: .le, text: "<=", location: loc)
            }
            return Token(kind: .lt, text: "<", location: loc)
        case ">":
            if index < chars.count && chars[index] == "=" {
                advance()
                return Token(kind: .ge, text: ">=", location: loc)
            }
            return Token(kind: .gt, text: ">", location: loc)
        case "&": return Token(kind: .amp, text: "&", location: loc)
        case ",": return Token(kind: .comma, text: ",", location: loc)
        case "(": return Token(kind: .lParen, text: "(", location: loc)
        case ")": return Token(kind: .rParen, text: ")", location: loc)
        case "{": return Token(kind: .lBrace, text: "{", location: loc)
        case "}": return Token(kind: .rBrace, text: "}", location: loc)
        case "+": return Token(kind: .plus, text: "+", location: loc)
        case "-": return Token(kind: .minus, text: "-", location: loc)
        case "*": return Token(kind: .star, text: "*", location: loc)
        case "/": return Token(kind: .slash, text: "/", location: loc)
        case "|": return Token(kind: .pipe, text: "|", location: loc)
        case "^": return Token(kind: .caret, text: "^", location: loc)
        case "~": return Token(kind: .tilde, text: "~", location: loc)
        case "=": return Token(kind: .equal, text: "=", location: loc)
        default:
            return Token(kind: .ident(String(c)), text: String(c), location: loc)
        }
    }

    mutating func tokenizeLine() -> [Token] {
        var tokens: [Token] = []
        while true {
            let t = next()
            if t.kind == .eof { break }
            if t.kind == .eol {
                tokens.append(t)
                break
            }
            tokens.append(t)
        }
        return tokens
    }

    mutating func tokenizeAll() -> [Token] {
        var tokens: [Token] = []
        while true {
            let t = next()
            tokens.append(t)
            if t.kind == .eof { break }
        }
        return tokens
    }

    // MARK: - Internals

    private mutating func readString(_ loc: SourceLocation) -> Token {
        advance() // "
        var result = ""
        while index < chars.count {
            let c = chars[index]
            if c == "\"" {
                advance()
                break
            }
            if c == "\n" { break }
            if c == "\\" && stringEscapes {
                advance()
                guard index < chars.count else { break }
                let e = chars[index]
                advance()
                switch e {
                case "n": result.append("\n")
                case "r": result.append("\r")
                case "t": result.append("\t")
                case "\\": result.append("\\")
                case "\"": result.append("\"")
                case "'": result.append("'")
                case "0": result.append("\0")
                default: result.append(e)
                }
            } else {
                result.append(c)
                advance()
            }
        }
        return Token(kind: .string(result), text: "\"...\"", location: loc)
    }

    private mutating func readChar(_ loc: SourceLocation) -> Token {
        advance() // '
        var value: UInt8 = 0
        if index < chars.count {
            if chars[index] == "\\" && stringEscapes {
                advance()
                if index < chars.count {
                    let e = chars[index]
                    advance()
                    switch e {
                    case "n": value = 0x0A
                    case "r": value = 0x0D
                    case "t": value = 0x09
                    case "\\": value = UInt8(ascii: "\\")
                    case "'": value = UInt8(ascii: "'")
                    case "0": value = 0
                    default:
                        value = UInt8(truncatingIfNeeded: e.unicodeScalars.first?.value ?? 0)
                    }
                }
            } else {
                value = UInt8(truncatingIfNeeded: chars[index].unicodeScalars.first?.value ?? 0)
                advance()
            }
        }
        if index < chars.count && chars[index] == "'" { advance() }
        return Token(kind: .char(value), text: "'...'", location: loc)
    }

    private mutating func readIdentChars() -> String {
        var s = ""
        while index < chars.count && chars[index].isIdentCont {
            s.append(chars[index])
            advance()
        }
        return s
    }

    private mutating func readWhile(_ pred: (Character) -> Bool) -> String {
        var s = ""
        while index < chars.count && pred(chars[index]) {
            s.append(chars[index])
            advance()
        }
        return s
    }

    private mutating func skipWhitespaceAndComments() {
        while index < chars.count {
            let c = chars[index]
            if c == " " || c == "\t" || c == "\r" {
                advance()
                continue
            }
            if c == ";" {
                while index < chars.count && chars[index] != "\n" { advance() }
                continue
            }
            break
        }
    }

    private func peekIsDigitOrBin() -> Bool {
        let n = index + 1
        guard n < chars.count else { return false }
        let c = chars[n]
        return c == "0" || c == "1"
    }

    private mutating func advance() {
        guard index < chars.count else { return }
        if chars[index] == "\n" {
            line += 1
            column = 1
        } else {
            column += 1
        }
        index += 1
    }

    private func location() -> SourceLocation {
        SourceLocation(file: file, line: line, column: column)
    }
}

private extension Character {
    var isIdentStart: Bool {
        isLetter || self == "_"
    }
    var isIdentCont: Bool {
        isLetter || isNumber || self == "_" || self == "@"
    }
    var isHexDigit: Bool {
        isNumber || ("a"..."f").contains(self) || ("A"..."F").contains(self)
    }
}
