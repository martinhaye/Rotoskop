import Foundation
import Testing
@testable import RotoskopUI

@Suite("Assembly keyboard suggestions")
struct AssemblyKeyboardSuggestionsTests {
    @Test func baselineWhenEmpty() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "")
        #expect(symbols.count == AssemblyKeyboardSuggestions.count)
        #expect(symbols == AssemblyKeyboardSuggestions.baseline)
    }

    @Test func ldaSpacePrefersImmediate() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\tlda ")
        #expect(symbols.first == "#")
        #expect(symbols.contains("("))
        #expect(symbols.contains("$"))
    }

    @Test func staSpacePrefersAbsoluteOrIndirect() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\tsta ")
        #expect(symbols.first == "$" || symbols.first == "(")
        #expect(symbols.contains("$"))
        #expect(symbols.contains("("))
    }

    @Test func jsrSpacePrefersLabels() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\tjsr ")
        #expect(symbols.first == "_")
    }

    @Test func afterHashPrefersHex() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\tlda #")
        #expect(symbols.first == "$")
    }

    @Test func insideQuotesPrefersEscape() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\t.byte \"hello")
        #expect(symbols.first == "\\")
    }

    @Test func branchPrefersLocalLabels() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\tbne ")
        #expect(symbols.first == ":" || symbols.first == "@")
    }

    @Test func afterTabPrefersDirectiveOrComment() {
        let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: "\t")
        #expect(symbols.first == ".")
        #expect(symbols.contains(";"))
    }

    @Test func alwaysReturnsTenUnique() {
        let samples = ["", "\tlda ", "\tlda #", "\tsta (", "msg: .byte \"a", "label:"]
        for sample in samples {
            let symbols = AssemblyKeyboardSuggestions.symbols(beforeCaret: sample)
            #expect(symbols.count == 10)
            #expect(Set(symbols).count == 10)
        }
    }
}
