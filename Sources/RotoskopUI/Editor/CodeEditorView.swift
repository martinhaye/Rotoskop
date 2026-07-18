import SwiftUI

#if os(iOS)
import UIKit

/// Disarmed UITextView editor with assembly Space/Tab/Enter rules and simple highlighting (DESIGN §3).
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var fileKind: EditorInputRules.FileKind

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> EditorTextView {
        let view = EditorTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .systemBackground
        view.textContainer.lineFragmentPadding = 8
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.alwaysBounceVertical = true
        view.keyboardDismissMode = .interactive
        view.allowsEditingTextAttributes = false
        view.smartDashesType = .no
        view.smartQuotesType = .no
        view.smartInsertDeleteType = .no
        view.autocorrectionType = .no
        view.autocapitalizationType = .none
        view.spellCheckingType = .no
        view.inlinePredictionType = .no
        view.dataDetectorTypes = []
        view.layoutManager.allowsNonContiguousLayout = false
        view.fileKind = fileKind
        view.inputAssistantItem.leadingBarButtonGroups = []
        view.inputAssistantItem.trailingBarButtonGroups = []
        view.undoManager?.removeAllActions()
        context.coordinator.applyAttributedText(to: view, string: text, forceCursor: nil)
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleSelectNotification),
            name: .rotoskopEditorSelect,
            object: nil
        )
        NotificationCenter.default.addObserver(
            context.coordinator,
            selector: #selector(Coordinator.handleSelectAllNotification),
            name: .rotoskopEditorSelectAll,
            object: nil
        )
        context.coordinator.editor = view
        return view
    }

    func updateUIView(_ uiView: EditorTextView, context: Context) {
        context.coordinator.parent = self
        context.coordinator.editor = uiView
        uiView.fileKind = fileKind
        if uiView.markedTextRange == nil, uiView.text != text {
            let selected = uiView.selectedRange
            context.coordinator.applyAttributedText(to: uiView, string: text, forceCursor: selected)
        }
    }

    static func dismantleUIView(_ uiView: EditorTextView, coordinator: Coordinator) {
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.editor = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditorView
        weak var editor: EditorTextView?
        private var isApplyingHighlight = false

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        @objc func handleSelectNotification() {
            editor?.enterSelectMode()
        }

        @objc func handleSelectAllNotification() {
            editor?.selectAll(nil)
            editor?.enterSelectMode()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let newText = textView.text ?? ""
            parent.text = newText
            let selected = textView.selectedRange
            applyAttributedText(to: textView, string: newText, forceCursor: selected)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard textView.markedTextRange == nil else { return true }

            if text == " " {
                let lineInfo = lineContext(in: textView, utf16Offset: range.location)
                let insertion = EditorInputRules.spaceInsertion(
                    kind: parent.fileKind,
                    line: lineInfo.line,
                    cursorUTF16Offset: lineInfo.offsetInLine
                )
                replace(in: textView, range: range, with: insertion)
                return false
            }

            if text == "\t" {
                replace(in: textView, range: range, with: EditorInputRules.tabInsertion())
                return false
            }

            if text == "\n" {
                let lineInfo = lineContext(in: textView, utf16Offset: range.location)
                let prefix = utf16Prefix(lineInfo.line, count: lineInfo.offsetInLine)
                let insertion = EditorInputRules.enterInsertion(
                    kind: parent.fileKind,
                    lineBeforeCursor: prefix
                )
                replace(in: textView, range: range, with: insertion)
                return false
            }

            return true
        }

        func applyAttributedText(to textView: UITextView, string: String, forceCursor: NSRange?) {
            isApplyingHighlight = true
            defer { isApplyingHighlight = false }

            let font = UIFont.systemFont(ofSize: 16, weight: .regular)
            let attributed = AssemblyHighlighter.attributedString(
                for: string,
                font: font,
                isAssembly: parent.fileKind == .assembly
            )
            textView.attributedText = attributed
            if let forceCursor {
                let maxLoc = (textView.text as NSString?)?.length ?? 0
                let loc = min(forceCursor.location, maxLoc)
                let len = min(forceCursor.length, max(0, maxLoc - loc))
                textView.selectedRange = NSRange(location: loc, length: len)
            }
        }

        private func replace(in textView: UITextView, range: NSRange, with replacement: String) {
            if let view = textView as? EditorTextView {
                view.replaceCommitted(range: range, with: replacement)
            } else {
                textView.textStorage.replaceCharacters(in: range, with: replacement)
            }
            textViewDidChange(textView)
        }

        private func lineContext(in textView: UITextView, utf16Offset: Int) -> (line: String, offsetInLine: Int) {
            let ns = textView.text as NSString? ?? ""
            let clamped = max(0, min(utf16Offset, ns.length))
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: clamped, length: 0))
            let line = ns.substring(with: NSRange(location: lineStart, length: contentsEnd - lineStart))
            return (line, clamped - lineStart)
        }

        private func utf16Prefix(_ string: String, count: Int) -> String {
            let ns = string as NSString
            let c = max(0, min(count, ns.length))
            return ns.substring(to: c)
        }
    }
}

/// UITextView with select-mode and near-cursor pan to move caret (DESIGN §3.6).
final class EditorTextView: UITextView, UIGestureRecognizerDelegate {
    var fileKind: EditorInputRules.FileKind = .plain
    private(set) var selectMode = false
    private var panStartNearCursor = false
    private var draggingCursor = false

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.delegate = self
        pan.cancelsTouchesInView = false
        addGestureRecognizer(pan)
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    func replaceCommitted(range: NSRange, with replacement: String) {
        let ns = text as NSString? ?? ""
        guard range.location <= ns.length else { return }
        let safeLen = min(range.length, ns.length - range.location)
        let safe = NSRange(location: range.location, length: safeLen)
        if undoManager != nil {
            // Prefer replace API so undo works.
            if let start = position(from: beginningOfDocument, offset: safe.location),
               let end = position(from: beginningOfDocument, offset: safe.location + safe.length),
               let textRange = textRange(from: start, to: end) {
                replace(textRange, withText: replacement)
                return
            }
        }
        textStorage.replaceCharacters(in: safe, with: replacement)
        selectedRange = NSRange(location: safe.location + (replacement as NSString).length, length: 0)
    }

    func enterSelectMode() {
        selectMode = true
        becomeFirstResponder()
        if selectedRange.length == 0 {
            selectedRange = wordRange(at: selectedRange.location)
        }
    }

    func exitSelectMode() {
        selectMode = false
    }

    private func wordRange(at location: Int) -> NSRange {
        let ns = text as NSString? ?? ""
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        let loc = max(0, min(location, ns.length - 1))
        let letters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "_.@"))
        var start = loc
        var end = loc
        while start > 0 {
            let ch = ns.character(at: start - 1)
            if let scalar = UnicodeScalar(ch), letters.contains(scalar) {
                start -= 1
            } else {
                break
            }
        }
        while end < ns.length {
            let ch = ns.character(at: end)
            if let scalar = UnicodeScalar(ch), letters.contains(scalar) {
                end += 1
            } else {
                break
            }
        }
        return NSRange(location: start, length: max(0, end - start))
    }

    @objc private func handlePan(_ gr: UIPanGestureRecognizer) {
        switch gr.state {
        case .began:
            let point = gr.location(in: self)
            let cursorRect = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
            panStartNearCursor = cursorRect.insetBy(dx: -28, dy: -28).contains(point)
            draggingCursor = selectMode || panStartNearCursor
            if draggingCursor && !selectMode {
                // Slow drag near cursor: move caret; disable scrolling for this gesture.
                isScrollEnabled = false
            }
        case .changed:
            guard draggingCursor else { return }
            let point = gr.location(in: self)
            guard let pos = closestPosition(to: point) else { return }
            if selectMode {
                let anchorOffset = selectedRange.location
                guard let anchor = position(from: beginningOfDocument, offset: anchorOffset) else { return }
                selectedTextRange = textRange(from: anchor, to: pos)
            } else {
                selectedTextRange = textRange(from: pos, to: pos)
            }
        case .ended, .cancelled, .failed:
            isScrollEnabled = true
            draggingCursor = false
            panStartNearCursor = false
        default:
            break
        }
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        true
    }

    override func copy(_ sender: Any?) {
        super.copy(sender)
        exitSelectMode()
    }

    override func cut(_ sender: Any?) {
        super.cut(sender)
        exitSelectMode()
    }

    override func paste(_ sender: Any?) {
        super.paste(sender)
        exitSelectMode()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        for press in presses {
            if press.key?.keyCode == .keyboardEscape {
                exitSelectMode()
                return
            }
        }
        super.pressesBegan(presses, with: event)
    }
}

#else

/// macOS package-build stub (iOS app uses the UIKit editor).
struct CodeEditorView: View {
    @Binding var text: String
    var fileKind: EditorInputRules.FileKind

    var body: some View {
        TextEditor(text: $text)
            .font(.body)
    }
}

#endif
