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

    @Test func assemblySpaceRules() {
        // Normal → tab
        #expect(EditorInputRules.spaceInsertion(kind: .assembly, line: "lda", cursorUTF16Offset: 3) == "\t")

        // After comma → space
        #expect(EditorInputRules.spaceInsertion(kind: .assembly, line: "lda #0,", cursorUTF16Offset: 7) == " ")

        // Inside quotes → space
        let quoted = "msg: .byte \"hello"
        #expect(EditorInputRules.spaceInsertion(kind: .assembly, line: quoted, cursorUTF16Offset: quoted.utf16.count) == " ")

        // In comment body → space
        let comment = "lda #0 ; note"
        #expect(EditorInputRules.spaceInsertion(kind: .assembly, line: comment, cursorUTF16Offset: comment.utf16.count) == " ")

        // Semicolon inside quotes is not a comment
        let fake = ".byte \"; not comment"
        #expect(EditorInputRules.spaceInsertion(kind: .assembly, line: fake, cursorUTF16Offset: fake.utf16.count) == " ")
    }

    @Test func plainSpaceAlwaysSpace() {
        #expect(EditorInputRules.spaceInsertion(kind: .plain, line: "key:", cursorUTF16Offset: 4) == " ")
    }

    @Test func enterAutoIndentPlainOnly() {
        #expect(EditorInputRules.enterInsertion(kind: .assembly, lineBeforeCursor: "\tlda") == "\n")
        #expect(EditorInputRules.enterInsertion(kind: .plain, lineBeforeCursor: "  key: x") == "\n  ")
        #expect(EditorInputRules.enterInsertion(kind: .plain, lineBeforeCursor: "\t- item") == "\n\t")
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
