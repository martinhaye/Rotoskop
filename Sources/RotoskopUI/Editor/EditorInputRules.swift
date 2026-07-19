import Foundation

/// Tab / Enter behavior for the code editor (DESIGN §3.1 / §3.3).
public enum EditorInputRules {
    public enum FileKind: Equatable, Sendable {
        case assembly
        case plain

        public static func kind(forRelativePath path: String) -> FileKind {
            let ext = (path as NSString).pathExtension.lowercased()
            return (ext == "s" || ext == "i") ? .assembly : .plain
        }
    }

    /// What to insert when the user presses Tab (always a tab character).
    public static func tabInsertion() -> String { "\t" }

    /// Text to insert for Enter: newline plus the leading whitespace of the current line.
    public static func enterInsertion(lineBeforeCursor: String) -> String {
        let indent = leadingWhitespace(of: lineBeforeCursor)
        return "\n" + indent
    }

    /// Leading whitespace to copy for plain Enter auto-indent.
    public static func leadingWhitespace(of line: String) -> String {
        String(line.prefix(while: { $0 == " " || $0 == "\t" }))
    }
}
