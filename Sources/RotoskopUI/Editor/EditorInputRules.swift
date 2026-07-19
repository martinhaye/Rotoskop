import Foundation

/// Tab / Space / Enter behavior for the code editor (DESIGN §3.1 / §3.3).
public enum EditorInputRules {
    public enum FileKind: Equatable, Sendable {
        case assembly
        case plain

        public static func kind(forRelativePath path: String) -> FileKind {
            let ext = (path as NSString).pathExtension.lowercased()
            return (ext == "s" || ext == "i") ? .assembly : .plain
        }
    }

    /// Result of pressing Space (may convert a prior space into a tab).
    public enum SpaceEdit: Equatable, Sendable {
        /// Insert `text` at the caret (normally a single space).
        case insert(String)
        /// Replace the space immediately before the caret with `\t`.
        case convertPrecedingSpaceToTab
    }

    /// What to do when the user presses Space.
    ///
    /// Double-space → tab (unified for all file kinds), except inside quotes or a comment body.
    public static func spaceEdit(
        kind: FileKind,
        line: String,
        cursorUTF16Offset: Int,
        replacingSelection: Bool = false
    ) -> SpaceEdit {
        let offset = clampUTF16(cursorUTF16Offset, in: line)
        if isInsideQuotes(line: line, cursorUTF16Offset: offset) {
            return .insert(" ")
        }
        if isInCommentBody(kind: kind, line: line, cursorUTF16Offset: offset) {
            return .insert(" ")
        }
        if !replacingSelection, isImmediatelyAfterSpace(line: line, cursorUTF16Offset: offset) {
            return .convertPrecedingSpaceToTab
        }
        return .insert(" ")
    }

    /// What to insert when the user presses Tab (always a tab character).
    public static func tabInsertion() -> String { "\t" }

    /// Text to insert for Enter, including auto-indent for non-assembly.
    public static func enterInsertion(kind: FileKind, lineBeforeCursor: String) -> String {
        switch kind {
        case .assembly:
            return "\n"
        case .plain:
            let indent = String(lineBeforeCursor.prefix(while: { $0 == " " || $0 == "\t" }))
            return "\n" + indent
        }
    }

    // MARK: - Context helpers

    /// Cursor is inside a double-quoted string on this line (quotes not counted as inside).
    public static func isInsideQuotes(line: String, cursorUTF16Offset: Int) -> Bool {
        let offset = clampUTF16(cursorUTF16Offset, in: line)
        var inside = false
        var i = line.utf16.startIndex
        var index = 0
        while i < line.utf16.endIndex, index < offset {
            let unit = line.utf16[i]
            if unit == 0x22 { // "
                inside.toggle()
            }
            i = line.utf16.index(after: i)
            index += 1
        }
        return inside
    }

    public static func isImmediatelyAfterSpace(line: String, cursorUTF16Offset: Int) -> Bool {
        let offset = clampUTF16(cursorUTF16Offset, in: line)
        guard offset > 0 else { return false }
        let idx = line.utf16.index(line.utf16.startIndex, offsetBy: offset - 1)
        return line.utf16[idx] == 0x20 // space
    }

    /// True when a comment starter appears before the cursor on this line, outside of quotes.
    /// Assembly: `;`. Plain: `#` (YAML-safe comments).
    public static func isInCommentBody(kind: FileKind, line: String, cursorUTF16Offset: Int) -> Bool {
        let starter: UInt16 = kind == .assembly ? 0x3B /* ; */ : 0x23 /* # */
        let offset = clampUTF16(cursorUTF16Offset, in: line)
        var insideQuotes = false
        var i = line.utf16.startIndex
        var index = 0
        while i < line.utf16.endIndex, index < offset {
            let unit = line.utf16[i]
            if unit == 0x22 { // "
                insideQuotes.toggle()
            } else if unit == starter, !insideQuotes {
                return true
            }
            i = line.utf16.index(after: i)
            index += 1
        }
        return false
    }

    /// Leading whitespace to copy for plain Enter auto-indent.
    public static func leadingWhitespace(of line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }

    private static func clampUTF16(_ offset: Int, in string: String) -> Int {
        max(0, min(offset, string.utf16.count))
    }
}
