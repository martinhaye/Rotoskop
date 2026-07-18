import Foundation

final class SymbolTable {
    struct Symbol {
        var value: Int
        var defined: Bool
        var isLabel: Bool
    }

    /// Index 0 = global (persists across passes). Higher = current .proc locals.
    private var scopes: [[String: Symbol]] = [[:]]
    private var scopeNames: [String] = []

    var cheapBase: String = ""
    var unnamed: [Int] = []

    func pushProc(_ name: String) {
        while scopes.count > 1 {
            scopes.removeLast()
            if !scopeNames.isEmpty { scopeNames.removeLast() }
        }
        scopeNames.append(name)
        var local: [String: Symbol] = [:]
        let prefix = name + "::"
        for (key, sym) in scopes[0] {
            if key.hasPrefix(prefix) {
                local[String(key.dropFirst(prefix.count))] = sym
            }
            // Cheap locals: "proc@foo" from prior pass
            let cheapPrefix = name + "@"
            if key.hasPrefix(cheapPrefix) {
                local["@" + String(key.dropFirst(cheapPrefix.count))] = sym
                local[key] = sym
            }
        }
        scopes.append(local)
        cheapBase = name
    }

    func popProc() {
        if scopes.count > 1 {
            scopes.removeLast()
            scopeNames.removeLast()
        }
    }

    var currentProc: String? { scopeNames.last }

    func define(_ name: String, value: Int, isLabel: Bool) {
        let key = resolveDefineKey(name)
        let sym = Symbol(value: value, defined: true, isLabel: isLabel)
        scopes[scopes.count - 1][key] = sym
        if let proc = currentProc {
            scopes[0]["\(proc)::\(key)"] = sym
        } else {
            scopes[0][key] = sym
        }
        if isLabel && !name.hasPrefix("@") && name != ":" {
            cheapBase = name
        }
    }

    func defineUnnamed(_ pc: Int) {
        unnamed.append(pc)
    }

    func lookup(_ name: String) -> Symbol? {
        let key = resolveLookupKey(name)
        for i in stride(from: scopes.count - 1, through: 0, by: -1) {
            if let s = scopes[i][key] { return s }
        }
        if let proc = currentProc, let s = scopes[0]["\(proc)::\(key)"] { return s }
        if name.contains("::"), let s = scopes[0][name] { return s }
        if let r = name.range(of: "::") {
            let proc = String(name[..<r.lowerBound])
            let label = String(name[r.upperBound...])
            if let s = scopes[0]["\(proc)::\(label)"] { return s }
        }
        return nil
    }

    func defineInProc(_ shortName: String, value: Int, isLabel: Bool) {
        let sym = Symbol(value: value, defined: true, isLabel: isLabel)
        scopes[scopes.count - 1][shortName] = sym
        if let proc = currentProc {
            scopes[0]["\(proc)::\(shortName)"] = sym
            // Proc entry point is globally visible; other locals stay scoped.
            if shortName == proc {
                scopes[0][shortName] = sym
            }
        }
        if isLabel && !shortName.hasPrefix("@") {
            cheapBase = shortName
        }
    }

    func unnamedForward(fromDefIndex: Int) -> Int? {
        fromDefIndex < unnamed.count ? unnamed[fromDefIndex] : nil
    }

    func unnamedBackward(fromDefIndex: Int) -> Int? {
        let idx = fromDefIndex - 1
        return (idx >= 0 && idx < unnamed.count) ? unnamed[idx] : nil
    }

    var unnamedDefinedCount: Int { unnamed.count }

    func resetPass() {
        unnamed = []
        cheapBase = ""
        let global = scopes.first ?? [:]
        scopes = [global]
        scopeNames = []
    }

    func clearAll() {
        scopes = [[:]]
        scopeNames = []
        unnamed = []
        cheapBase = ""
    }

    private func resolveDefineKey(_ name: String) -> String {
        name.hasPrefix("@") ? cheapBase + name : name
    }

    private func resolveLookupKey(_ name: String) -> String {
        name.hasPrefix("@") ? cheapBase + name : name
    }
}

/// Expression evaluator over a token slice.
struct ExprParser {
    var tokens: [Token]
    var pos = 0
    var symbols: SymbolTable
    var pc: Int
    var stringEscapes: Bool
    var diagnostics: [Diagnostic] = []
    var location: SourceLocation
    var unnamedCursor: Int

    init(tokens: [Token], symbols: SymbolTable, pc: Int, location: SourceLocation, unnamedCursor: Int, stringEscapes: Bool = true) {
        self.tokens = tokens
        self.symbols = symbols
        self.pc = pc
        self.location = location
        self.unnamedCursor = unnamedCursor
        self.stringEscapes = stringEscapes
    }

    mutating func parse() -> Int? {
        guard pos < tokens.count else { return nil }
        return parseOr()
    }

    private mutating func parseOr() -> Int? {
        guard var left = parseXor() else { return nil }
        while match(.pipe) {
            guard let right = parseXor() else { return nil }
            left |= right
        }
        return left
    }

    private mutating func parseXor() -> Int? {
        guard var left = parseAnd() else { return nil }
        while match(.caret) {
            guard let right = parseAnd() else { return nil }
            left ^= right
        }
        return left
    }

    private mutating func parseAnd() -> Int? {
        guard var left = parseAdd() else { return nil }
        while true {
            guard case .amp = peek()?.kind else { break }
            pos += 1
            guard let right = parseAdd() else { return nil }
            left &= right
        }
        return left
    }

    private mutating func parseAdd() -> Int? {
        guard var left = parseMul() else { return nil }
        while true {
            if match(.plus) {
                guard let right = parseMul() else { return nil }
                left += right
            } else if match(.minus) {
                guard let right = parseMul() else { return nil }
                left -= right
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseMul() -> Int? {
        guard var left = parseUnary() else { return nil }
        while true {
            if match(.star) {
                guard let right = parseUnary() else { return nil }
                left *= right
            } else if match(.slash) {
                guard let right = parseUnary() else { return nil }
                if right == 0 {
                    diag("division by zero")
                    return nil
                }
                left /= right
            } else {
                break
            }
        }
        return left
    }

    private mutating func parseUnary() -> Int? {
        if match(.minus) {
            guard let v = parseUnary() else { return nil }
            return -v
        }
        if match(.tilde) {
            guard let v = parseUnary() else { return nil }
            return ~v
        }
        if match(.lt) {
            guard let v = parseUnary() else { return nil }
            return v & 0xFF
        }
        if match(.gt) {
            guard let v = parseUnary() else { return nil }
            return (v >> 8) & 0xFF
        }
        return parsePrimary()
    }

    private mutating func parsePrimary() -> Int? {
        guard let t = peek() else { return nil }

        if case .dotIdent(let name) = t.kind {
            return parsePseudo(name)
        }
        if case .number(let n) = t.kind {
            pos += 1
            return n
        }
        if case .char(let c) = t.kind {
            pos += 1
            return Int(c)
        }
        if case .star = t.kind {
            pos += 1
            return pc
        }

        if case .colon = t.kind {
            pos += 1
            if match(.plus) {
                if let v = symbols.unnamedForward(fromDefIndex: unnamedCursor) {
                    return v
                }
                return 0
            }
            if match(.minus) {
                if let v = symbols.unnamedBackward(fromDefIndex: unnamedCursor) {
                    return v
                }
                diag("backward unnamed label :- not found")
                return nil
            }
            diag("unexpected ':' in expression")
            return nil
        }

        if case .ident(let name) = t.kind {
            pos += 1
            var full = name
            if case .colonColon = peek()?.kind {
                pos += 1
                guard case .ident(let lab) = peek()?.kind else {
                    diag("expected label after ::")
                    return nil
                }
                pos += 1
                full = name + "::" + lab
            }
            if let sym = symbols.lookup(full), sym.defined {
                return sym.value
            }
            return nil
        }

        if match(.lParen) {
            guard let v = parseOr() else { return nil }
            guard match(.rParen) else {
                diag("expected ')'")
                return nil
            }
            return v
        }

        diag("unexpected token in expression: \(t.text)")
        return nil
    }

    private mutating func parsePseudo(_ name: String) -> Int? {
        pos += 1
        switch name {
        case "strlen":
            guard match(.lParen) else { diag("expected ("); return nil }
            guard case .string(let s) = peek()?.kind else { diag(".strlen needs string"); return nil }
            pos += 1
            guard match(.rParen) else { diag("expected )"); return nil }
            return s.count
        default:
            diag("unsupported pseudo-function .\(name)")
            return nil
        }
    }

    private mutating func match(_ kind: TokenKind) -> Bool {
        guard let t = peek(), t.kind == kind else { return false }
        pos += 1
        return true
    }

    private func peek() -> Token? {
        guard pos < tokens.count else { return nil }
        let t = tokens[pos]
        if t.kind == .eol || t.kind == .eof { return nil }
        return t
    }

    private mutating func diag(_ msg: String) {
        diagnostics.append(Diagnostic(.error, msg, at: location))
    }
}
