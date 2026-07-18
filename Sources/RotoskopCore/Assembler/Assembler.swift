import Foundation

/// ca65-subset assembler: one source → raw binary (+ listing).
public final class Assembler {
    private var options: AssembleOptions
    private var diagnostics: [Diagnostic] = []
    private var symbols = SymbolTable()
    private var pc: Int = 0
    private var minAddr: Int = Int.max
    private var maxAddr: Int = Int.min
    private var memory: [UInt8?] = Array(repeating: nil, count: 0x10000)
    private var stringEscapes = false
    private var macros: [String: MacroDef] = [:]
    private var listingLines: [String] = []
    private var pass = 0
    private var suppressEmit = false // .if false branches
    private var ifStack: [IfFrame] = []
    private var macroLocalCounter = 0
    private var skippingMacroBody = false
    /// Pending branch/data fixups for `:+` (unnamed index → list of patch sites).
    private var unnamedForwardFixups: [Int: [(patchAddr: Int, basePC: Int, isRelative: Bool)]] = [:]

    private struct MacroDef {
        var params: [String]
        var body: [[Token]] // lines of tokens
    }

    private struct IfFrame {
        var active: Bool      // currently assembling
        var seenTrue: Bool
        var inElse: Bool
    }

    public init(options: AssembleOptions = AssembleOptions()) {
        self.options = options
    }

    public func assemble(file path: String) -> AssembleResult {
        diagnostics = []
        do {
            let src = try String(contentsOfFile: path, encoding: .utf8)
            return assemble(source: src, file: path)
        } catch {
            diagnostics.append(Diagnostic(.error, "cannot read \(path): \(error)"))
            return AssembleResult(binary: [], baseAddress: 0, listing: "", diagnostics: diagnostics)
        }
    }

    public func assemble(source: String, file: String) -> AssembleResult {
        diagnostics = []
        symbols.clearAll()
        macros = [:]
        memory = Array(repeating: nil, count: 0x10000)
        stringEscapes = false
        listingLines = []
        macroLocalCounter = 0

        collectMacros(source: source, file: file)

        var lastFingerprint = ""
        for p in 1...4 {
            pass = p
            pc = 0
            minAddr = Int.max
            maxAddr = Int.min
            memory = Array(repeating: nil, count: 0x10000)
            symbols.resetPass()
            ifStack = []
            suppressEmit = false
            listingLines = []
            skippingMacroBody = false
            unnamedForwardFixups = [:]
            processFile(source: source, file: file, isInclude: false)
            let fp = fingerprint()
            if fp == lastFingerprint && p > 1 { break }
            lastFingerprint = fp
        }

        var binary: [UInt8] = []
        var base: UInt16 = 0
        if minAddr <= maxAddr {
            base = UInt16(minAddr)
            for a in minAddr...maxAddr {
                binary.append(memory[a] ?? 0x00)
            }
        }

        let listing = options.generateListing ? listingLines.joined(separator: "\n") + "\n" : ""
        return AssembleResult(binary: binary, baseAddress: base, listing: listing, diagnostics: diagnostics)
    }

    private func fingerprint() -> String {
        var parts: [String] = []
        if minAddr <= maxAddr {
            for a in minAddr...maxAddr {
                parts.append(String(format: "%02X", memory[a] ?? 0xFF))
            }
        }
        return parts.joined()
    }

    // MARK: - File processing

    private func processFile(source: String, file: String, isInclude: Bool) {
        var lexer = Lexer(source: source, file: file, stringEscapes: stringEscapes)
        var lineTokens: [Token] = []
        var lineStart = SourceLocation(file: file, line: 1)

        func flushLine() {
            defer { lineTokens = [] }
            let trimmed = lineTokens.filter { $0.kind != .eol && $0.kind != .eof }
            guard !trimmed.isEmpty else { return }
            processLine(trimmed, location: lineStart)
        }

        while true {
            let t = lexer.next()
            // Update lexer escapes dynamically
            lexer.stringEscapes = stringEscapes
            if lineTokens.isEmpty { lineStart = t.location }
            if t.kind == .eof {
                flushLine()
                break
            }
            if t.kind == .eol {
                flushLine()
                continue
            }
            lineTokens.append(t)
        }
    }

    private func processLine(_ tokens: [Token], location: SourceLocation) {
        // Skip macro bodies entirely (already collected), except .endmacro
        if skippingMacroBody {
            if case .dotIdent(let d) = tokens.first?.kind, d == "endmacro" {
                skippingMacroBody = false
            }
            return
        }

        // Handle conditional assembly directives even when suppressed
        if case .dotIdent(let d) = tokens.first?.kind {
            switch d {
            case "if":
                handleIf(Array(tokens.dropFirst()), location: location)
                return
            case "elseif":
                handleElseif(Array(tokens.dropFirst()), location: location)
                return
            case "else":
                handleElse(location: location)
                return
            case "endif":
                handleEndif(location: location)
                return
            case "macro":
                skippingMacroBody = true
                return
            case "endmacro":
                error("orphaned .endmacro", at: location)
                return
            default:
                break
            }
        }

        if suppressEmit { return }

        // Labels: name: or bare :
        var rest = tokens
        while let (label, remaining) = eatLabel(rest) {
            defineLabel(label, at: location)
            rest = remaining
        }

        guard let first = rest.first else { return }

        // Equate: name = expr
        if rest.count >= 2, case .ident = rest[0].kind, case .equal = rest[1].kind {
            handleEquate(rest, location: location)
            return
        }

        // Directive
        if case .dotIdent(let dir) = first.kind {
            handleDirective(dir, Array(rest.dropFirst()), location: location)
            return
        }

        // Macro invocation or instruction
        if case .ident(let name) = first.kind {
            let lower = name.lowercased()
            if macros[lower] != nil {
                expandMacro(lower, args: Array(rest.dropFirst()), location: location)
                return
            }
            if Opcodes.lookup(lower) != nil {
                assembleInstruction(lower, operandTokens: Array(rest.dropFirst()), location: location)
                return
            }
            error("unknown instruction or macro '\(name)'", at: location)
            return
        }

        error("unexpected statement", at: location)
    }

    private func isLabelPosition(_ tokens: [Token], _ i: Int) -> Bool { i == 0 }

    private func eatLabel(_ tokens: [Token]) -> (String, [Token])? {
        guard let first = tokens.first else { return nil }

        // Unnamed `:` not followed by + or - as part of label def at BOL
        if case .colon = first.kind {
            if tokens.count > 1 {
                if case .plus = tokens[1].kind { return nil }
                if case .minus = tokens[1].kind { return nil }
            }
            // `:` alone defines unnamed; if more tokens follow on same line, still define
            return (":", Array(tokens.dropFirst()))
        }

        guard case .ident(let name) = first.kind else { return nil }
        guard tokens.count >= 2, case .colon = tokens[1].kind else { return nil }
        // `bcc :+` / `bne :-` — colon belongs to unnamed ref, not a label def
        if tokens.count >= 3 {
            if case .plus = tokens[2].kind { return nil }
            if case .minus = tokens[2].kind { return nil }
        }
        return (name, Array(tokens.dropFirst(2)))
    }

    private func defineLabel(_ name: String, at location: SourceLocation) {
        if name == ":" {
            let idx = symbols.unnamedDefinedCount
            symbols.defineUnnamed(pc)
            if let fixups = unnamedForwardFixups[idx] {
                for fix in fixups {
                    if fix.isRelative {
                        let offset = pc - fix.basePC
                        if offset >= -128 && offset <= 127 {
                            memory[fix.patchAddr] = UInt8(bitPattern: Int8(offset))
                        }
                    } else {
                        memory[fix.patchAddr] = UInt8(pc & 0xFF)
                        if fix.patchAddr + 1 < 0x10000 {
                            memory[fix.patchAddr + 1] = UInt8((pc >> 8) & 0xFF)
                        }
                    }
                }
                unnamedForwardFixups[idx] = nil
            }
            noteListing(pc, bytes: [], source: ":", location: location)
            return
        }
        if name.hasPrefix("@") {
            // Cheap locals keyed by cheapBase+name in global for multi-pass
            symbols.define(name, value: pc, isLabel: true)
        } else if symbols.currentProc != nil {
            symbols.defineInProc(name, value: pc, isLabel: true)
        } else {
            symbols.define(name, value: pc, isLabel: true)
        }
        noteListing(pc, bytes: [], source: "\(name):", location: location)
    }

    // MARK: - Equates & directives

    private func handleEquate(_ tokens: [Token], location: SourceLocation) {
        guard case .ident(let name) = tokens[0].kind else { return }
        let exprTokens = Array(tokens.dropFirst(2))
        if let v = evalExpr(exprTokens, location: location) {
            if symbols.currentProc != nil {
                symbols.defineInProc(name, value: v, isLabel: false)
            } else {
                symbols.define(name, value: v, isLabel: false)
            }
            noteListing(pc, bytes: [], source: "\(name) = \(v)", location: location)
        } else if pass < 4 {
            // forward — leave undefined
            symbols.define(name, value: 0, isLabel: false)
        } else {
            error("cannot evaluate equate '\(name)'", at: location)
        }
    }

    private func handleDirective(_ dir: String, _ args: [Token], location: SourceLocation) {
        switch dir {
        case "org":
            if let v = evalExpr(args, location: location) {
                pc = v & 0xFFFF
            }
        case "byt", "byte":
            emitData(args, word: false, location: location)
        case "word":
            emitData(args, word: true, location: location)
        case "res":
            handleRes(args, location: location)
        case "align":
            handleAlign(args, location: location)
        case "include":
            handleInclude(args, location: location)
        case "proc":
            if case .ident(let name) = args.first?.kind {
                symbols.pushProc(name)
                symbols.defineInProc(name, value: pc, isLabel: true) // proc name = start
                // Also define global label for jsr
                symbols.define(name, value: pc, isLabel: true)
            }
        case "endproc":
            symbols.popProc()
        case "feature":
            if case .ident(let f) = args.first?.kind, f.lowercased() == "string_escapes" {
                stringEscapes = true
            }
        case "error":
            let msg: String
            if case .string(let s) = args.first?.kind { msg = s }
            else { msg = "error directive" }
            error(msg, at: location)
        case "local":
            // Macro-local symbol — define unique label placeholder
            for t in args {
                if case .ident(let name) = t.kind {
                    macroLocalCounter += 1
                    let uniq = ".\(name)_\(macroLocalCounter)"
                    symbols.define(name, value: pc, isLabel: true) // will be set at label use
                    _ = uniq
                }
            }
        default:
            error("unsupported directive .\(dir)", at: location)
        }
    }

    private func handleRes(_ args: [Token], location: SourceLocation) {
        let parts = splitComma(args)
        guard let count = evalExpr(parts[0], location: location) else { return }
        var fill: UInt8 = 0
        if parts.count > 1, let f = evalExpr(parts[1], location: location) {
            fill = UInt8(f & 0xFF)
        }
        var bytes: [UInt8] = []
        for _ in 0..<count {
            emitByte(fill)
            bytes.append(fill)
        }
        noteListing(pc - bytes.count, bytes: bytes, source: ".res", location: location)
    }

    private func handleAlign(_ args: [Token], location: SourceLocation) {
        let parts = splitComma(args)
        guard let boundary = evalExpr(parts[0], location: location), boundary > 0 else { return }
        var fill: UInt8 = 0
        if parts.count > 1, let f = evalExpr(parts[1], location: location) {
            fill = UInt8(f & 0xFF)
        }
        while (pc % boundary) != 0 {
            emitByte(fill)
        }
    }

    private func handleInclude(_ args: [Token], location: SourceLocation) {
        guard case .string(let name) = args.first?.kind else {
            error(".include needs a string path", at: location)
            return
        }
        guard let path = resolveInclude(name) else {
            error("include not found: \(name)", at: location)
            return
        }
        do {
            let src = try String(contentsOfFile: path, encoding: .utf8)
            processFile(source: src, file: path, isInclude: true)
        } catch {
            self.error("cannot read include \(path)", at: location)
        }
    }

    private func resolveInclude(_ name: String) -> String? {
        if FileManager.default.fileExists(atPath: name) { return name }
        for dir in options.includePaths {
            let p = (dir as NSString).appendingPathComponent(name)
            if FileManager.default.fileExists(atPath: p) { return p }
        }
        return nil
    }

    private func emitData(_ args: [Token], word: Bool, location: SourceLocation) {
        let parts = splitComma(args)
        var bytes: [UInt8] = []
        let start = pc
        for part in parts {
            if part.count == 1, case .string(let s) = part[0].kind {
                for ch in s.utf8 {
                    emitByte(ch)
                    bytes.append(ch)
                }
                continue
            }
            if let v = evalExpr(part, location: location) {
                if word {
                    emitByte(UInt8(v & 0xFF))
                    emitByte(UInt8((v >> 8) & 0xFF))
                    bytes.append(UInt8(v & 0xFF))
                    bytes.append(UInt8((v >> 8) & 0xFF))
                } else {
                    emitByte(UInt8(v & 0xFF))
                    bytes.append(UInt8(v & 0xFF))
                }
            } else {
                // forward: emit placeholder
                if word {
                    emitByte(0); emitByte(0)
                    bytes.append(0); bytes.append(0)
                } else {
                    emitByte(0)
                    bytes.append(0)
                }
            }
        }
        noteListing(start, bytes: bytes, source: word ? ".word" : ".byte", location: location)
    }

    // MARK: - Instructions

    private func assembleInstruction(_ mnem: String, operandTokens: [Token], location: SourceLocation) {
        guard let entries = Opcodes.lookup(mnem) else { return }
        let start = pc

        // Implied / accum with no operands
        if operandTokens.isEmpty {
            if let e = entries.first(where: { $0.mode == .implied || $0.mode == .accum }) {
                emitByte(e.opcode)
                noteListing(start, bytes: [e.opcode], source: mnem, location: location)
                return
            }
            error("\(mnem) needs an operand", at: location)
            return
        }

        // Accumulator: A
        if operandTokens.count == 1, case .ident(let a) = operandTokens[0].kind, a.lowercased() == "a" {
            if let e = entries.first(where: { $0.mode == .accum }) {
                emitByte(e.opcode)
                noteListing(start, bytes: [e.opcode], source: "\(mnem) A", location: location)
                return
            }
        }

        // Relative branches
        if let e = entries.first(where: { $0.mode == .relative }) {
            // Special-case :+ / :- for reliable unnamed fixups
            if operandTokens.count >= 2,
               case .colon = operandTokens[0].kind,
               case .plus = operandTokens[1].kind {
                let idx = symbols.unnamedDefinedCount // next unnamed
                let next = pc + 2
                emitByte(e.opcode)
                let patch = pc
                emitByte(0)
                if let target = symbols.unnamedForward(fromDefIndex: idx) {
                    let offset = target - next
                    memory[patch] = UInt8(bitPattern: Int8(max(-128, min(127, offset))))
                } else {
                    unnamedForwardFixups[idx, default: []].append((patch, next, true))
                }
                noteListing(start, bytes: [e.opcode, memory[patch] ?? 0], source: mnem, location: location)
                return
            }
            if operandTokens.count >= 2,
               case .colon = operandTokens[0].kind,
               case .minus = operandTokens[1].kind {
                let target = symbols.unnamedBackward(fromDefIndex: symbols.unnamedDefinedCount) ?? (pc + 2)
                let next = pc + 2
                var offset = target - next
                if offset < -128 || offset > 127 {
                    if pass >= 4 { error("branch out of range", at: location) }
                    offset = 0
                }
                let off8 = Int8(max(-128, min(127, offset)))
                emitByte(e.opcode)
                emitByte(UInt8(bitPattern: off8))
                noteListing(start, bytes: [e.opcode, UInt8(bitPattern: off8)], source: mnem, location: location)
                return
            }
            let target = evalExpr(operandTokens, location: location) ?? (pc + 2)
            let next = pc + 2
            var offset = target - next
            if offset < -128 || offset > 127 {
                if pass >= 4 { error("branch out of range", at: location) }
                offset = 0
            }
            let off8 = Int8(max(-128, min(127, offset)))
            emitByte(e.opcode)
            emitByte(UInt8(bitPattern: off8))
            noteListing(start, bytes: [e.opcode, UInt8(bitPattern: off8)], source: mnem, location: location)
            return
        }

        // Immediate: #expr
        if case .hash = operandTokens.first?.kind {
            let expr = Array(operandTokens.dropFirst())
            let v = evalExpr(expr, location: location) ?? 0
            guard let e = entries.first(where: { $0.mode == .imm }) else {
                error("\(mnem) does not support immediate", at: location)
                return
            }
            emitByte(e.opcode)
            emitByte(UInt8(v & 0xFF))
            noteListing(start, bytes: [e.opcode, UInt8(v & 0xFF)], source: "\(mnem) #", location: location)
            return
        }

        // (zp),Y
        if case .lParen = operandTokens.first?.kind {
            if let (zpExpr, rest) = parseIndY(operandTokens) {
                let v = evalExpr(zpExpr, location: location) ?? 0
                guard let e = entries.first(where: { $0.mode == .indY }) else {
                    error("\(mnem) does not support (zp),Y", at: location)
                    return
                }
                emitByte(e.opcode)
                emitByte(UInt8(v & 0xFF))
                noteListing(start, bytes: [e.opcode, UInt8(v & 0xFF)], source: "\(mnem) (),Y", location: location)
                _ = rest
                return
            }
            // JMP (abs)
            if mnem == "jmp", let e = entries.first(where: { $0.mode == .ind }) {
                // (expr)
                var inner = Array(operandTokens.dropFirst())
                if let last = inner.last, case .rParen = last.kind {
                    inner = Array(inner.dropLast())
                }
                let v = evalExpr(inner, location: location) ?? 0
                emitByte(e.opcode)
                emitByte(UInt8(v & 0xFF))
                emitByte(UInt8((v >> 8) & 0xFF))
                return
            }
        }

        // abs/zp with optional ,X or ,Y
        let parts = splitComma(operandTokens)
        let addrExpr = parts[0]
        var index: String? = nil
        if parts.count > 1, case .ident(let x) = parts[1].first?.kind {
            index = x.lowercased()
        }

        let addr = evalExpr(addrExpr, location: location)
        let forceAbs = addr.map { $0 > 0xFF } ?? true // unknown → abs to be safe on early passes... 
        // Actually for ZP labels like tmp=$6, we need zp. If unresolved, assume abs then fix on later pass — size change!
        // Size stability: if symbol defined as zp equate, use zp; if label >$FF use abs; if unknown use abs (3 bytes) consistently after defined.

        let mode: AddrMode
        let value: Int
        if let a = addr {
            value = a
            if index == "x" {
                mode = a <= 0xFF && entries.contains(where: { $0.mode == .zpX }) ? .zpX : .absX
                // Prefer zpX if value fits and zpX exists
                if a <= 0xFF && entries.contains(where: { $0.mode == .zpX }) {
                    // ok
                }
            } else if index == "y" {
                mode = a <= 0xFF && entries.contains(where: { $0.mode == .zpY }) ? .zpY : .absY
            } else {
                mode = a <= 0xFF && entries.contains(where: { $0.mode == .zp }) ? .zp : .abs
            }
        } else {
            value = 0
            // Forward ref: use abs/absX/absY to keep size stable
            if index == "x" { mode = .absX }
            else if index == "y" { mode = .absY }
            else { mode = .abs }
        }

        // Refine mode selection
        let chosen: AddrMode = {
            if index == "x" {
                if value <= 0xFF && addr != nil && entries.contains(where: { $0.mode == .zpX }) { return .zpX }
                return .absX
            }
            if index == "y" {
                if value <= 0xFF && addr != nil && entries.contains(where: { $0.mode == .zpY }) { return .zpY }
                return .absY
            }
            if value <= 0xFF && addr != nil && entries.contains(where: { $0.mode == .zp }) { return .zp }
            return .abs
        }()
        _ = mode
        _ = forceAbs

        guard let e = entries.first(where: { $0.mode == chosen })
                ?? entries.first(where: { $0.mode == .abs || $0.mode == .absX || $0.mode == .absY }) else {
            error("no addressing mode for \(mnem)", at: location)
            return
        }

        emitByte(e.opcode)
        var bytes: [UInt8] = [e.opcode]
        if e.size >= 2 {
            emitByte(UInt8(value & 0xFF))
            bytes.append(UInt8(value & 0xFF))
        }
        if e.size >= 3 {
            emitByte(UInt8((value >> 8) & 0xFF))
            bytes.append(UInt8((value >> 8) & 0xFF))
        }
        noteListing(start, bytes: bytes, source: mnem, location: location)
    }

    private func parseIndY(_ tokens: [Token]) -> ([Token], [Token])? {
        // (expr),Y or (expr),y
        guard case .lParen = tokens.first?.kind else { return nil }
        var depth = 0
        var endParen = -1
        for (idx, t) in tokens.enumerated() {
            if case .lParen = t.kind { depth += 1 }
            if case .rParen = t.kind {
                depth -= 1
                if depth == 0 { endParen = idx; break }
            }
        }
        guard endParen > 0 else { return nil }
        let inner = Array(tokens[1..<endParen])
        let after = Array(tokens[(endParen + 1)...])
        // Expect ,Y
        guard after.count >= 2, case .comma = after[0].kind,
              case .ident(let y) = after[1].kind, y.lowercased() == "y" else {
            return nil
        }
        return (inner, after)
    }

    // MARK: - Conditionals (basic numeric / presence)

    private func handleIf(_ args: [Token], location: SourceLocation) {
        let parentActive = ifStack.last?.active ?? true
        let cond = evaluateCondition(args, location: location)
        let active = parentActive && cond
        ifStack.append(IfFrame(active: active, seenTrue: cond, inElse: false))
        suppressEmit = !(ifStack.last?.active ?? true)
    }

    private func handleElseif(_ args: [Token], location: SourceLocation) {
        guard !ifStack.isEmpty else { error(".elseif without .if", at: location); return }
        var frame = ifStack[ifStack.count - 1]
        let parentActive = ifStack.dropLast().last?.active ?? true
        if frame.seenTrue {
            frame.active = false
        } else {
            let cond = evaluateCondition(args, location: location)
            frame.active = parentActive && cond
            if cond { frame.seenTrue = true }
        }
        ifStack[ifStack.count - 1] = frame
        suppressEmit = !(ifStack.last?.active ?? true)
    }

    private func handleElse(location: SourceLocation) {
        guard !ifStack.isEmpty else { error(".else without .if", at: location); return }
        var frame = ifStack[ifStack.count - 1]
        let parentActive = ifStack.dropLast().last?.active ?? true
        frame.active = parentActive && !frame.seenTrue
        frame.inElse = true
        ifStack[ifStack.count - 1] = frame
        suppressEmit = !(ifStack.last?.active ?? true)
    }

    private func handleEndif(location: SourceLocation) {
        guard !ifStack.isEmpty else { error(".endif without .if", at: location); return }
        ifStack.removeLast()
        suppressEmit = !(ifStack.last?.active ?? true)
    }

    private func evaluateCondition(_ args: [Token], location: SourceLocation) -> Bool {
        // Support .if .match(...) / .xmatch(...) / numeric
        if let first = args.first, case .dotIdent(let n) = first.kind {
            if n == "match" || n == "xmatch" {
                return evaluateMatch(exact: n == "xmatch", tokens: args, location: location)
            }
        }
        // Parenthesized .match
        if case .lParen = args.first?.kind {
            // (.match (...)) or (.xmatch (...))
            var inner = Array(args.dropFirst())
            if let last = inner.last, case .rParen = last.kind { inner = Array(inner.dropLast()) }
            if let f = inner.first, case .dotIdent(let n) = f.kind, n == "match" || n == "xmatch" {
                return evaluateMatch(exact: n == "xmatch", tokens: inner, location: location)
            }
            if let v = evalExpr(args, location: location) { return v != 0 }
        }
        if let v = evalExpr(args, location: location) { return v != 0 }
        return false
    }

    private func evaluateMatch(exact: Bool, tokens: [Token], location: SourceLocation) -> Bool {
        // .match ( a , b )  or .match (.left(...), #)
        guard tokens.count >= 2 else { return false }
        // Skip .match
        var i = 1
        guard i < tokens.count, case .lParen = tokens[i].kind else { return false }
        i += 1
        let (left, next) = readMatchArg(tokens, start: i)
        i = next
        guard i < tokens.count, case .comma = tokens[i].kind else { return false }
        i += 1
        let (right, _) = readMatchArg(tokens, start: i)
        return tokenListsMatch(left, right, exact: exact)
    }

    private func readMatchArg(_ tokens: [Token], start: Int) -> ([Token], Int) {
        var i = start
        if i < tokens.count, case .lBrace = tokens[i].kind {
            i += 1
            var depth = 1
            var out: [Token] = []
            while i < tokens.count && depth > 0 {
                if case .lBrace = tokens[i].kind { depth += 1 }
                if case .rBrace = tokens[i].kind {
                    depth -= 1
                    if depth == 0 { i += 1; break }
                }
                if depth > 0 { out.append(tokens[i]) }
                i += 1
            }
            return (out, i)
        }
        // Single token or .left(...) call — gather until comma or rparen at depth 0
        var depth = 0
        var out: [Token] = []
        while i < tokens.count {
            let t = tokens[i]
            if case .lParen = t.kind { depth += 1 }
            if case .rParen = t.kind {
                if depth == 0 { break }
                depth -= 1
            }
            if case .comma = t.kind, depth == 0 { break }
            out.append(t)
            i += 1
        }
        // Expand .left / .right / .tcount in isolation for match args — simplified:
        out = expandTokenFuncs(out)
        return (out, i)
    }

    private func expandTokenFuncs(_ tokens: [Token]) -> [Token] {
        // Handle .left(n, {list}), .right(n, {list}), .tcount({list})
        var result: [Token] = []
        var i = 0
        while i < tokens.count {
            if case .dotIdent(let name) = tokens[i].kind {
                if name == "left" || name == "right" || name == "tcount" {
                    if let (expanded, next) = evalTokenFunc(name, tokens, start: i) {
                        result.append(contentsOf: expanded)
                        i = next
                        continue
                    }
                }
                if name == "strlen" {
                    // leave for expr — as number token if possible
                    if let (val, next) = evalStrlen(tokens, start: i) {
                        result.append(Token(kind: .number(val), text: "\(val)", location: tokens[i].location))
                        i = next
                        continue
                    }
                }
            }
            result.append(tokens[i])
            i += 1
        }
        return result
    }

    private func evalStrlen(_ tokens: [Token], start: Int) -> (Int, Int)? {
        var i = start + 1
        guard i < tokens.count, case .lParen = tokens[i].kind else { return nil }
        i += 1
        guard i < tokens.count, case .string(let s) = tokens[i].kind else { return nil }
        i += 1
        guard i < tokens.count, case .rParen = tokens[i].kind else { return nil }
        i += 1
        return (s.count, i)
    }

    private func evalTokenFunc(_ name: String, _ tokens: [Token], start: Int) -> ([Token], Int)? {
        var i = start + 1
        guard i < tokens.count, case .lParen = tokens[i].kind else { return nil }
        i += 1
        if name == "tcount" {
            let (list, next) = readMatchArg(tokens, start: i)
            i = next
            if i < tokens.count, case .rParen = tokens[i].kind { i += 1 }
            let loc = tokens[start].location
            return ([Token(kind: .number(list.count), text: "\(list.count)", location: loc)], i)
        }
        // left/right: first arg count, second list
        let (countToks, next1) = readMatchArg(tokens, start: i)
        i = next1
        guard i < tokens.count, case .comma = tokens[i].kind else { return nil }
        i += 1
        let (list, next2) = readMatchArg(tokens, start: i)
        i = next2
        if i < tokens.count, case .rParen = tokens[i].kind { i += 1 }
        let n = evalExpr(countToks, location: tokens[start].location) ?? 0
        if name == "left" {
            return (Array(list.prefix(max(0, n))), i)
        } else {
            return (Array(list.suffix(max(0, n))), i)
        }
    }

    private func tokenListsMatch(_ a: [Token], _ b: [Token], exact: Bool) -> Bool {
        let a2 = expandTokenFuncs(a)
        let b2 = expandTokenFuncs(b)
        guard a2.count == b2.count else { return false }
        for (x, y) in zip(a2, b2) {
            if exact {
                if !tokenExactEqual(x, y) { return false }
            } else {
                if !tokenLooseEqual(x, y) { return false }
            }
        }
        return true
    }

    private func tokenExactEqual(_ a: Token, _ b: Token) -> Bool {
        switch (a.kind, b.kind) {
        case (.ident(let x), .ident(let y)): return x.lowercased() == y.lowercased()
        case (.number(let x), .number(let y)): return x == y
        case (.hash, .hash), (.amp, .amp), (.lt, .lt), (.gt, .gt): return true
        case (.string(let x), .string(let y)): return x == y
        case (.char(let x), .char(let y)): return x == y
        default: return a.kind == b.kind && a.text.lowercased() == b.text.lowercased()
        }
    }

    private func tokenLooseEqual(_ a: Token, _ b: Token) -> Bool {
        // ca65 .match is looser — same token type often matches
        tokenExactEqual(a, b)
    }

    // MARK: - Macros

    private func expandMacro(_ name: String, args: [Token], location: SourceLocation) {
        guard let def = macros[name] else { return }
        let argLists = splitMacroArgs(args)
        // .paramcount = number of args given
        var bindings: [String: [Token]] = [:]
        for (idx, param) in def.params.enumerated() {
            if idx < argLists.count {
                bindings[param] = argLists[idx]
            } else {
                bindings[param] = []
            }
        }
        // Also support .paramcount as special — rewrite in body
        let paramCount = argLists.count

        for line in def.body {
            var substituted = substituteMacro(line, bindings: bindings, paramCount: paramCount)
            substituted = expandTokenFuncs(substituted)
            // Handle .local
            if case .dotIdent(let d) = substituted.first?.kind, d == "local" {
                for t in substituted.dropFirst() {
                    if case .ident(let n) = t.kind {
                        macroLocalCounter += 1
                        let uniq = "\(n)__m\(macroLocalCounter)"
                        bindings[n] = [Token(kind: .ident(uniq), text: uniq, location: t.location)]
                        symbols.define(uniq, value: 0, isLabel: true)
                    }
                }
                continue
            }
            processLine(substituted, location: location)
        }
    }

    private func substituteMacro(_ line: [Token], bindings: [String: [Token]], paramCount: Int) -> [Token] {
        var out: [Token] = []
        var i = 0
        while i < line.count {
            let t = line[i]
            if case .dotIdent(let d) = t.kind, d == "paramcount" {
                out.append(Token(kind: .number(paramCount), text: "\(paramCount)", location: t.location))
                i += 1
                continue
            }
            // .ident(.concat(.string(func), "_arg0")) — expand later via expandIdentConcat
            if case .ident(let name) = t.kind, let repl = bindings[name] {
                out.append(contentsOf: repl)
                i += 1
                continue
            }
            out.append(t)
            i += 1
        }
        return expandIdentConcat(out)
    }

    private func expandIdentConcat(_ tokens: [Token]) -> [Token] {
        // Replace .ident(.concat(.string(x), "y")) with ident
        var result: [Token] = []
        var i = 0
        while i < tokens.count {
            if case .dotIdent(let n) = tokens[i].kind, n == "ident" {
                if let (ident, next) = parseIdentConcat(tokens, start: i) {
                    result.append(Token(kind: .ident(ident), text: ident, location: tokens[i].location))
                    i = next
                    continue
                }
            }
            if case .dotIdent(let n) = tokens[i].kind, n == "string" {
                // .string(foo) → "foo"
                var j = i + 1
                if j < tokens.count, case .lParen = tokens[j].kind {
                    j += 1
                    if j < tokens.count, case .ident(let id) = tokens[j].kind {
                        j += 1
                        if j < tokens.count, case .rParen = tokens[j].kind { j += 1 }
                        result.append(Token(kind: .string(id), text: "\"\(id)\"", location: tokens[i].location))
                        i = j
                        continue
                    }
                }
            }
            result.append(tokens[i])
            i += 1
        }
        return result
    }

    private func parseIdentConcat(_ tokens: [Token], start: Int) -> (String, Int)? {
        // .ident ( .concat ( .string ( name ) , "suffix" ) )
        var i = start + 1
        guard i < tokens.count, case .lParen = tokens[i].kind else { return nil }
        i += 1
        guard i < tokens.count, case .dotIdent(let c) = tokens[i].kind, c == "concat" else { return nil }
        i += 1
        guard i < tokens.count, case .lParen = tokens[i].kind else { return nil }
        i += 1
        // first string
        var parts: [String] = []
        while i < tokens.count {
            if case .dotIdent(let s) = tokens[i].kind, s == "string" {
                i += 1
                guard i < tokens.count, case .lParen = tokens[i].kind else { return nil }
                i += 1
                guard i < tokens.count, case .ident(let id) = tokens[i].kind else { return nil }
                parts.append(id)
                i += 1
                guard i < tokens.count, case .rParen = tokens[i].kind else { return nil }
                i += 1
            } else if case .string(let s) = tokens[i].kind {
                parts.append(s)
                i += 1
            } else if case .comma = tokens[i].kind {
                i += 1
            } else if case .rParen = tokens[i].kind {
                i += 1
                break
            } else {
                return nil
            }
        }
        // closing of .ident(
        if i < tokens.count, case .rParen = tokens[i].kind { i += 1 }
        return (parts.joined(), i)
    }

    private func splitMacroArgs(_ tokens: [Token]) -> [[Token]] {
        // Split on commas at depth 0; respect braces
        var result: [[Token]] = []
        var current: [Token] = []
        var depth = 0
        var brace = 0
        for t in tokens {
            if case .lParen = t.kind { depth += 1 }
            if case .rParen = t.kind { depth -= 1 }
            if case .lBrace = t.kind { brace += 1 }
            if case .rBrace = t.kind { brace -= 1 }
            if case .comma = t.kind, depth == 0, brace == 0 {
                // Strip outer braces from arg
                result.append(stripBraces(current))
                current = []
                continue
            }
            current.append(t)
        }
        if !current.isEmpty || !result.isEmpty {
            result.append(stripBraces(current))
        }
        return result.filter { !$0.isEmpty || result.count > 1 }
    }

    private func stripBraces(_ tokens: [Token]) -> [Token] {
        guard tokens.count >= 2,
              case .lBrace = tokens.first?.kind,
              case .rBrace = tokens.last?.kind else { return tokens }
        return Array(tokens.dropFirst().dropLast())
    }

    // MARK: - Prepass for macros

    /// Must be called to register macros before assemble — integrated into assemble().
    fileprivate func collectMacros(source: String, file: String) {
        var lexer = Lexer(source: source, file: file, stringEscapes: stringEscapes)
        var collecting: (name: String, params: [String], body: [[Token]], loc: SourceLocation)?
        var line: [Token] = []

        func flush() {
            let t = line.filter { $0.kind != .eol }
            line = []
            guard !t.isEmpty else { return }
            if var c = collecting {
                if case .dotIdent(let d) = t.first?.kind, d == "endmacro" {
                    macros[c.name] = MacroDef(params: c.params, body: c.body)
                    collecting = nil
                    return
                }
                c.body.append(t)
                collecting = c
                return
            }
            if case .dotIdent(let d) = t.first?.kind, d == "macro" {
                // .macro name p1, p2
                guard t.count >= 2, case .ident(let name) = t[1].kind else { return }
                var params: [String] = []
                let rest = Array(t.dropFirst(2))
                for part in splitComma(rest) {
                    if case .ident(let p) = part.first?.kind {
                        params.append(p)
                    }
                }
                collecting = (name.lowercased(), params, [], t[0].location)
                return
            }
            // Also scan includes for macros
            if case .dotIdent(let d) = t.first?.kind, d == "include" {
                if case .string(let name) = t.dropFirst().first?.kind, let path = resolveInclude(name) {
                    if let src = try? String(contentsOfFile: path, encoding: .utf8) {
                        collectMacros(source: src, file: path)
                    }
                }
            }
        }

        while true {
            let tok = lexer.next()
            if tok.kind == .eof { flush(); break }
            if tok.kind == .eol { flush(); continue }
            line.append(tok)
        }
    }

    // MARK: - Helpers

    private func emitByte(_ b: UInt8) {
        let addr = pc & 0xFFFF
        memory[addr] = b
        minAddr = min(minAddr, addr)
        maxAddr = max(maxAddr, addr)
        pc = (pc + 1) & 0xFFFF
    }

    private func evalExpr(_ tokens: [Token], location: SourceLocation) -> Int? {
        let expanded = expandTokenFuncs(tokens)
        var parser = ExprParser(
            tokens: expanded,
            symbols: symbols,
            pc: pc,
            location: location,
            unnamedCursor: symbols.unnamedDefinedCount,
            stringEscapes: stringEscapes
        )
        let v = parser.parse()
        diagnostics.append(contentsOf: parser.diagnostics)
        return v
    }

    private func splitComma(_ tokens: [Token]) -> [[Token]] {
        var result: [[Token]] = []
        var current: [Token] = []
        var depth = 0
        for t in tokens {
            if case .lParen = t.kind { depth += 1 }
            if case .rParen = t.kind { depth -= 1 }
            if case .comma = t.kind, depth == 0 {
                if !current.isEmpty { result.append(current) }
                current = []
                continue
            }
            current.append(t)
        }
        if !current.isEmpty { result.append(current) }
        return result
    }

    private func noteListing(_ addr: Int, bytes: [UInt8], source: String, location: SourceLocation) {
        guard options.generateListing, pass >= 2 else { return }
        let hex = bytes.prefix(8).map { String(format: "%02X", $0) }.joined(separator: " ")
        listingLines.append(String(format: "%04X: %-24@ %@", addr, hex as NSString, source as NSString))
    }

    private func error(_ msg: String, at location: SourceLocation) {
        if pass >= 4 || msg.contains("unsupported") || msg.contains("not found") || msg.contains("error directive") {
            diagnostics.append(Diagnostic(.error, msg, at: location))
        }
    }
}
