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

    @Test func singleSpaceInsertsSpace() {
        #expect(
            EditorInputRules.spaceEdit(kind: .assembly, line: "lda", cursorUTF16Offset: 3)
                == .insert(" ")
        )
        #expect(
            EditorInputRules.spaceEdit(kind: .plain, line: "key:", cursorUTF16Offset: 4)
                == .insert(" ")
        )
    }

    @Test func doubleSpaceConvertsToTab() {
        #expect(
            EditorInputRules.spaceEdit(kind: .assembly, line: "lda ", cursorUTF16Offset: 4)
                == .convertPrecedingSpaceToTab
        )
        #expect(
            EditorInputRules.spaceEdit(kind: .plain, line: "key: ", cursorUTF16Offset: 5)
                == .convertPrecedingSpaceToTab
        )
    }

    @Test func spaceRulesInsideQuotesAndComments() {
        // Inside quotes → space (even after a space)
        let quoted = "msg: .byte \"hello "
        #expect(
            EditorInputRules.spaceEdit(kind: .assembly, line: quoted, cursorUTF16Offset: quoted.utf16.count)
                == .insert(" ")
        )

        // In assembly comment body → space (even after a space)
        let comment = "lda #0 ; note "
        #expect(
            EditorInputRules.spaceEdit(kind: .assembly, line: comment, cursorUTF16Offset: comment.utf16.count)
                == .insert(" ")
        )

        // In plain (#) comment body → space
        let yamlComment = "key: x # note "
        #expect(
            EditorInputRules.spaceEdit(kind: .plain, line: yamlComment, cursorUTF16Offset: yamlComment.utf16.count)
                == .insert(" ")
        )

        // Semicolon inside quotes is not a comment; trailing space still converts
        let fake = ".byte \"; not comment\" "
        #expect(
            EditorInputRules.spaceEdit(kind: .assembly, line: fake, cursorUTF16Offset: fake.utf16.count)
                == .convertPrecedingSpaceToTab
        )
    }

    @Test func replacingSelectionDoesNotConvert() {
        #expect(
            EditorInputRules.spaceEdit(
                kind: .assembly,
                line: "lda ",
                cursorUTF16Offset: 4,
                replacingSelection: true
            ) == .insert(" ")
        )
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
