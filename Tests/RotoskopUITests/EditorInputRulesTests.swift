import Foundation
import Testing
@testable import RotoskopUI

@Suite("Editor input rules")
struct EditorInputRulesTests {
    @Test func fileKindFromExtension() {
        #expect(EditorInputRules.FileKind.kind(forRelativePath: "src/boot.s") == .assembly)
        #expect(EditorInputRules.FileKind.kind(forRelativePath: "include/base.i") == .assembly)
        #expect(EditorInputRules.FileKind.kind(forRelativePath: "rotoskop.yaml") == .plain)
        #expect(EditorInputRules.FileKind.kind(forRelativePath: "README.md") == .plain)
    }

    @Test func tabInsertsTab() {
        #expect(EditorInputRules.tabInsertion() == "\t")
    }

    @Test func enterAutoIndentCopiesLeadingWhitespace() {
        #expect(EditorInputRules.enterInsertion(lineBeforeCursor: "\tlda") == "\n\t")
        #expect(EditorInputRules.enterInsertion(lineBeforeCursor: "\t\tsta $00") == "\n\t\t")
        #expect(EditorInputRules.enterInsertion(lineBeforeCursor: "label:") == "\n")
        #expect(EditorInputRules.enterInsertion(lineBeforeCursor: "  key: x") == "\n  ")
        #expect(EditorInputRules.enterInsertion(lineBeforeCursor: "\t- item") == "\n\t")
    }

    @Test func highlighterFindsCommentOpcodeDirective() {
        let text = "start:\tlda #$01 ; load\n\t.byte \"hi\"\n"
        let tokens = AssemblyHighlighter.tokens(in: text)
        let kinds = tokens.map(\.kind)
        #expect(kinds.contains(.label))
        #expect(kinds.contains(.opcode))
        #expect(kinds.contains(.number))
        #expect(kinds.contains(.comment))
        #expect(kinds.contains(.directive))
        #expect(kinds.contains(.string))
    }
}
