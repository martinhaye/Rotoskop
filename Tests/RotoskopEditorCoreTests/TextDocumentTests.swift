import XCTest
@testable import RotoskopEditorCore

final class TextDocumentTests: XCTestCase {

    func testEmptyDocumentHasOneLine() {
        let doc = TextDocument()
        XCTAssertEqual(doc.lineCount, 1)
    }

    func testLineCounting() {
        let doc = TextDocument("LDA #$01\nSTA $0400\nBRK")
        XCTAssertEqual(doc.lineCount, 3)
        XCTAssertEqual(doc.lines.map(String.init), ["LDA #$01", "STA $0400", "BRK"])
    }

    func testTrailingNewlineYieldsEmptyFinalLine() {
        let doc = TextDocument("A\n")
        XCTAssertEqual(doc.lineCount, 2)
    }

    func testLineAtOffset() {
        let doc = TextDocument("abc\ndef\nghi")
        XCTAssertEqual(doc.line(atUTF8Offset: 0), 0)
        XCTAssertEqual(doc.line(atUTF8Offset: 4), 1)   // 'd'
        XCTAssertEqual(doc.line(atUTF8Offset: 8), 2)   // 'g'
    }

    func testReplace() {
        var doc = TextDocument("old")
        doc.replace(with: "new\ntext")
        XCTAssertEqual(doc.lineCount, 2)
    }
}
