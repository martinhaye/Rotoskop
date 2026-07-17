//
//  TextDocument.swift
//  RotoskopEditorCore
//
//  A minimal, platform-agnostic text document model backing the code editor.
//  The actual editing view (a stripped-down UITextView with the iOS "helpful"
//  behaviours disabled) lives in the app; this type holds the buffer and the
//  line-index bookkeeping the editor and emulator tooling share.
//

/// An editable text buffer with cheap line lookup.
public struct TextDocument {
    /// The full text of the document.
    public private(set) var text: String {
        didSet { recomputeLineStarts() }
    }

    /// UTF-8-offset start index of each line (always begins with 0).
    public private(set) var lineStarts: [Int] = [0]

    public init(_ text: String = "") {
        self.text = text
        recomputeLineStarts()
    }

    /// Number of lines (a trailing newline yields a final empty line).
    public var lineCount: Int { lineStarts.count }

    /// The lines of the document as substrings (without their terminators).
    public var lines: [Substring] {
        text.split(separator: "\n", omittingEmptySubsequences: false)
    }

    /// Replaces the whole document text.
    public mutating func replace(with newText: String) {
        text = newText
    }

    /// Returns the 0-based line number containing the given UTF-8 offset.
    public func line(atUTF8Offset offset: Int) -> Int {
        // Binary search over line starts.
        var lo = 0, hi = lineStarts.count - 1, result = 0
        while lo <= hi {
            let mid = (lo + hi) / 2
            if lineStarts[mid] <= offset {
                result = mid
                lo = mid + 1
            } else {
                hi = mid - 1
            }
        }
        return result
    }

    private mutating func recomputeLineStarts() {
        var starts = [0]
        var offset = 0
        for byte in text.utf8 {
            offset += 1
            if byte == 0x0A { starts.append(offset) }
        }
        lineStarts = starts
    }
}
