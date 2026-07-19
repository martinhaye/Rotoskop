import Foundation

/// Adaptive top-row symbol suggestions for the assembly keyboard.
///
/// Rankings come from `for_ref/runix` hand-written `.s`/`.i` (immediate character
/// runs collapsed). Opcode and punctuation heuristics boost the strongest contexts
/// (e.g. `lda ` → `#` first).
public enum AssemblyKeyboardSuggestions {
    public static let count = 10

    /// Global frequency fallback (Runix, runs collapsed).
    public static let baseline: [String] = [
        "\"", ".", "\\", ";", ",", "$", "_", ":", "=", "*",
    ]

    /// Suggest up to ``count`` symbols given the text before the caret.
    public static func symbols(beforeCaret: String) -> [String] {
        let line = currentLine(beforeCaret)
        var ranked: [String] = []

        func append(_ items: [String]) {
            for item in items where !ranked.contains(item) {
                ranked.append(item)
                if ranked.count >= count { return }
            }
        }

        if let opcode = trailingOpcode(in: line) {
            append(afterOpcode[opcode] ?? familySuggestions(for: opcode))
        }

        if isInsideQuotes(line) {
            append(["\\", "\"", ",", "$", "_", "'", "%", "-", ".", "#"])
        }

        if let last = line.last {
            if let list = afterChar[last] {
                append(list)
            }
            append(punctuationHeuristics(after: last))
        }

        if line.isEmpty, !beforeCaret.isEmpty {
            // Caret on an empty line (text above exists) — start-of-line priors.
            append(afterChar["\n"] ?? [";", ".", ":", "@", "_"])
        }

        append(baseline)
        return Array(ranked.prefix(count))
    }

    // MARK: - Context

    private static func currentLine(_ beforeCaret: String) -> String {
        if let idx = beforeCaret.lastIndex(of: "\n") {
            return String(beforeCaret[beforeCaret.index(after: idx)...])
        }
        return beforeCaret
    }

    /// `lda ` / `.byte ` / `jsr ` — ident with trailing whitespace at end of line.
    private static func trailingOpcode(in line: String) -> String? {
        let trimmedEnd = line.replacingOccurrences(of: "[ \t]+$", with: "", options: .regularExpression)
        guard trimmedEnd.count < line.count else { return nil }
        guard let match = trimmedEnd.range(of: "[.A-Za-z_][A-Za-z0-9_]*$", options: .regularExpression) else {
            return nil
        }
        let word = String(trimmedEnd[match])
        // Don't treat a lone register/operand letter after comma as an opcode.
        if trimmedEnd.contains(","), word.count == 1 { return nil }
        return word.lowercased()
    }

    private static func isInsideQuotes(_ line: String) -> Bool {
        var inside = false
        for ch in line where ch == "\"" {
            inside.toggle()
        }
        return inside
    }

    // MARK: - Tables (from Runix pair / opcode+space stats)

    /// High-signal previous characters only (digits/letters omitted — font dumps skew them).
    private static let afterChar: [Character: [String]] = [
        " ": ["\"", "$", ".", ";", "#", "=", "(", "-", "&", "_"],
        "\t": [".", ";", "=", "*", "+", "("],
        "\n": [";", ".", ":", "@", "_"],
        "#": ["$", "'", ">", "<", ")"],
        "$": [",", ")", ";", "'", "\""],
        "\"": [",", "-", "\\", "_", ")", ".", "#", "%"],
        "'": [",", ")", ";", "\""],
        "(": [".", "$", "'", "#", ")"],
        ")": [",", "-", ".", "/", "\"", "%"],
        ":": ["\"", "+", "-", "'", ";"],
        ";": ["*", ".", "@"],
        "=": ["%", "$", "\"", "'", "#"],
        ",": ["\"", "$", "'", "#", "("],
        ".": ["\\", "'", "\"", "$", "("],
        "-": [">", "$", "'", "(", "\\", "\""],
        "+": ["(", "$", "#", "'"],
        "*": ["+", "-", ",", ";", ")"],
        "/": ["\"", "*", ","],
        "\\": ["\"", "'", ",", "$", "%"],
        "_": [",", ")", ";", ".", "+"],
        "&": ["\"", "$", "#", "_"],
        "%": ["\"", ",", ")"],
        "<": ["\"", "#", "$", "'"],
        ">": ["\"", ",", ")", ";"],
        "@": [",", ")", ";", ":"],
    ]

    private static let afterOpcode: [String: [String]] = [
        "lda": ["#", "(", "$", "*"],
        "ldx": ["#", "*", "$"],
        "ldy": ["#", "*", "$"],
        "sta": ["$", "(", "_", "@"],
        "stx": ["$", "_", "@"],
        "sty": ["$", "_", "@"],
        "cmp": ["#", "(", "$", "-"],
        "cpx": ["#", "$"],
        "cpy": ["#", "$"],
        "adc": ["#", "(", "$"],
        "sbc": ["#", "(", "$"],
        "and": ["#", "(", "$"],
        "ora": ["#", "(", "$"],
        "eor": ["#", "(", "$"],
        "bit": ["$", "(", "#", "-"],
        "jmp": ["_", "$", "@", "("],
        "jsr": ["_", "$", "@"],
        "bne": [":", "@", "*"],
        "beq": ["@", ":"],
        "bcc": [":", "@"],
        "bcs": [":", "@"],
        "bmi": [":", "@"],
        "bpl": [":", "@"],
        "bvc": [":", "@"],
        "bvs": [":", "@"],
        "ldax": ["#", "&", "$"],
        "stax": ["$", "&", "_"],
        "print": ["\""],
        "fatal": ["\""],
        "include": ["\""],
        ".include": ["\""],
        "byte": ["$", "\"", ","],
        ".byte": ["$", "\"", ","],
        ".byt": ["\"", "$", ","],
        "word": ["$", ",", "#"],
        ".word": ["$", ",", "#"],
        "org": ["$"],
        ".org": ["$"],
        "proc": ["_"],
        ".proc": ["_"],
        ".if": ["(", "."],
        ".elseif": ["(", "."],
        ".ifdef": ["("],
        ".ifndef": ["("],
        // Implied ops often followed by comment
        "rts": [";"],
        "rti": [";"],
        "sec": [";", "="],
        "clc": [";", "="],
        "pha": [";"],
        "pla": [";"],
        "php": [";"],
        "plp": [";"],
        "tax": [";"],
        "tay": [";"],
        "txa": [";"],
        "tya": [";"],
        "tsx": [";"],
        "txs": [";"],
        "inx": [";"],
        "iny": [";"],
        "dex": [";"],
        "dey": [";"],
        "nop": [";"],
    ]

    private static func familySuggestions(for opcode: String) -> [String] {
        let loads: Set = [
            "lda", "ldx", "ldy", "cmp", "cpx", "cpy", "adc", "sbc", "and", "ora", "eor",
        ]
        let stores: Set = [
            "sta", "stx", "sty", "inc", "dec", "asl", "lsr", "rol", "ror", "trb", "tsb",
        ]
        if loads.contains(opcode) { return ["#", "(", "$", "*", "<", ">"] }
        if stores.contains(opcode) { return ["$", "(", "_", "@"] }
        if opcode.first == "b", opcode.count == 3 { return [":", "@", "*"] }
        if opcode == "jmp" || opcode == "jsr" { return ["_", "$", "@", "("] }
        if opcode.hasPrefix("."), opcode.contains("byte") { return ["$", "\"", ","] }
        if opcode.hasPrefix("."), opcode.contains("include") { return ["\""] }
        if opcode.hasPrefix(".if") { return ["(", "."] }
        return []
    }

    private static func punctuationHeuristics(after last: Character) -> [String] {
        switch last {
        case "#": return ["$", "'", "<", ">", "(", ")"]
        case "(": return ["$", "#", ")", ".", "'"]
        case ")": return [",", ";", "-", ".", ":"]
        case "=": return ["$", "#", "%", "\"", "'"]
        case ":": return ["\"", "+", "-", ";", "'"]
        case ",": return ["$", "#", "(", "\"", "'"]
        case "\"": return ["\\", ",", "\"", "$", "_"]
        default: return []
        }
    }
}
