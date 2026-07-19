import SwiftUI

#if os(iOS)
import UIKit

/// Disarmed UITextView editor with Space/Tab/Enter rules and simple highlighting (DESIGN §3).
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var fileKind: EditorInputRules.FileKind
    var filePath: String?
    var restoredScrollY: CGFloat
    var onScrollYChange: ((CGFloat) -> Void)?
    var revealLine: Int?
    var revealColumn: Int?
    var onRevealConsumed: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> EditorTextView {
        let view = EditorTextView()
        view.delegate = context.coordinator
        view.backgroundColor = .systemBackground
        view.textContainer.lineFragmentPadding = 8
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        // Critical for SwiftUI: don't hug content height or the view grows with the
        // document and UITextView never scrolls.
        view.setContentHuggingPriority(.defaultLow, for: .vertical)
        view.setContentHuggingPriority(.defaultLow, for: .horizontal)
        view.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        view.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        view.isScrollEnabled = true
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
        context.coordinator.trackedPath = filePath
        context.coordinator.restoreScroll(restoredScrollY, in: view)
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

        let pathChanged = context.coordinator.trackedPath != filePath
        if pathChanged {
            context.coordinator.trackedPath = filePath
            context.coordinator.isApplyingHighlight = true
            context.coordinator.applyAttributedText(to: uiView, string: text, forceCursor: NSRange(location: 0, length: 0))
            context.coordinator.isApplyingHighlight = false
            context.coordinator.restoreScroll(restoredScrollY, in: uiView)
        } else if uiView.markedTextRange == nil, uiView.text != text {
            let selected = uiView.selectedRange
            context.coordinator.applyAttributedText(to: uiView, string: text, forceCursor: selected)
        }

        if let line = revealLine {
            context.coordinator.reveal(line: line, column: revealColumn ?? 1, in: uiView)
            DispatchQueue.main.async {
                onRevealConsumed?()
            }
        }
    }

    static func dismantleUIView(_ uiView: EditorTextView, coordinator: Coordinator) {
        coordinator.parent.onScrollYChange?(uiView.contentOffset.y)
        uiView.teardownOverlays()
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.editor = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate {
        var parent: CodeEditorView
        weak var editor: EditorTextView?
        var trackedPath: String?
        var isApplyingHighlight = false
        private var suppressScrollCallback = false

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

        func restoreScroll(_ y: CGFloat, in textView: UITextView) {
            suppressScrollCallback = true
            textView.layoutIfNeeded()
            let maxY = max(0, textView.contentSize.height - textView.bounds.height)
            let target = min(max(0, y), maxY)
            textView.setContentOffset(CGPoint(x: 0, y: target), animated: false)
            // Layout may still be settling after attributed text; nudge once more.
            DispatchQueue.main.async { [weak self, weak textView] in
                guard let self, let textView else { return }
                let maxY = max(0, textView.contentSize.height - textView.bounds.height)
                textView.setContentOffset(CGPoint(x: 0, y: min(max(0, y), maxY)), animated: false)
                self.suppressScrollCallback = false
            }
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressScrollCallback else { return }
            parent.onScrollYChange?(scrollView.contentOffset.y)
        }

        func reveal(line: Int, column: Int, in textView: UITextView) {
            let ns = textView.text as NSString? ?? ""
            guard ns.length > 0 else { return }
            var currentLine = 1
            var index = 0
            while index < ns.length && currentLine < line {
                if ns.character(at: index) == 10 { // \n
                    currentLine += 1
                }
                index += 1
            }
            var lineEnd = index
            while lineEnd < ns.length, ns.character(at: lineEnd) != 10 {
                lineEnd += 1
            }
            let col = max(1, column)
            let caret = min(index + col - 1, lineEnd)
            let range = NSRange(location: caret, length: 0)
            textView.selectedRange = range
            textView.scrollRangeToVisible(NSRange(location: index, length: max(1, lineEnd - index)))
            textView.becomeFirstResponder()
        }

        func textViewDidChange(_ textView: UITextView) {
            guard !isApplyingHighlight else { return }
            let newText = textView.text ?? ""
            parent.text = newText
            let selected = textView.selectedRange
            applyAttributedText(to: textView, string: newText, forceCursor: selected)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            guard !isApplyingHighlight,
                  let editor = textView as? EditorTextView,
                  !editor.selectMode,
                  !editor.isDraggingCaret,
                  editor.selectedRange.length > 0
            else { return }
            // Tap / double-tap must only move the caret unless ⋯ Select mode is on (DESIGN §3.6).
            let caret = editor.selectedRange.location + editor.selectedRange.length
            editor.selectedRange = NSRange(location: caret, length: 0)
        }

        func textView(
            _ textView: UITextView,
            editMenuForTextIn range: NSRange,
            suggestedActions: [UIMenuElement]
        ) -> UIMenu? {
            guard let editor = textView as? EditorTextView, editor.selectMode else {
                return nil
            }
            return UIMenu(children: suggestedActions)
        }

        func textView(
            _ textView: UITextView,
            shouldChangeTextIn range: NSRange,
            replacementText text: String
        ) -> Bool {
            guard textView.markedTextRange == nil else { return true }

            if text == " " {
                let lineInfo = lineContext(in: textView, utf16Offset: range.location)
                let edit = EditorInputRules.spaceEdit(
                    kind: parent.fileKind,
                    line: lineInfo.line,
                    cursorUTF16Offset: lineInfo.offsetInLine,
                    replacingSelection: range.length > 0
                )
                switch edit {
                case .insert(let insertion):
                    replace(in: textView, range: range, with: insertion)
                case .convertPrecedingSpaceToTab:
                    let expanded = NSRange(location: range.location - 1, length: range.length + 1)
                    replace(in: textView, range: expanded, with: "\t")
                }
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

            let font = EditorCodingFont.make()
            let attributed = AssemblyHighlighter.attributedString(
                for: string,
                font: font,
                isAssembly: parent.fileKind == .assembly
            )
            textView.font = font
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

/// UITextView with select-mode, near-caret pan to move caret, and a simple loupe (DESIGN §3.6).
final class EditorTextView: UITextView, UIGestureRecognizerDelegate {
    var fileKind: EditorInputRules.FileKind = .plain
    private(set) var selectMode = false
    private var draggingCursor = false
    private var selectionAnchor: Int?
    private weak var caretDrag: UIPanGestureRecognizer?
    private let loupe = CaretLoupeView()
    private let dragCaret: UIView = {
        let v = UIView()
        v.backgroundColor = .systemBlue
        v.isUserInteractionEnabled = false
        v.isHidden = true
        return v
    }()
    private var savedTintColor: UIColor?

    /// True while we are programmatically moving the caret so selection guards don't fight us.
    private(set) var isDraggingCaret = false

    override var intrinsicContentSize: CGSize {
        // Let SwiftUI assign the tab's bounds; growing with text prevents scrolling.
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Pan (not long-press): began/changed fire immediately. shouldBegin limits it to
        // near-caret so scroll pans elsewhere still win.
        let drag = UIPanGestureRecognizer(target: self, action: #selector(handleCaretDrag(_:)))
        drag.delegate = self
        drag.maximumNumberOfTouches = 1
        addGestureRecognizer(drag)
        caretDrag = drag
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        disarmSystemSelectionGestures()
    }

    @discardableResult
    override func becomeFirstResponder() -> Bool {
        let ok = super.becomeFirstResponder()
        disarmSystemSelectionGestures()
        return ok
    }

    /// Kill stock double-tap / loupe selection; keep our caret-drag recognizer.
    private func disarmSystemSelectionGestures() {
        for recognizer in gestureRecognizers ?? [] {
            if recognizer === caretDrag { continue }
            if let tap = recognizer as? UITapGestureRecognizer, tap.numberOfTapsRequired >= 2 {
                tap.isEnabled = false
            }
            if recognizer is UILongPressGestureRecognizer {
                recognizer.isEnabled = false
            }
        }
    }

    func replaceCommitted(range: NSRange, with replacement: String) {
        let ns = text as NSString? ?? ""
        guard range.location <= ns.length else { return }
        let safeLen = min(range.length, ns.length - range.location)
        let safe = NSRange(location: range.location, length: safeLen)
        if undoManager != nil {
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
        selectionAnchor = nil
        if selectedRange.length > 0 {
            selectedRange = NSRange(location: selectedRange.location, length: 0)
        }
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

    private func isNearCursor(_ boundsPoint: CGPoint) -> Bool {
        let cursorRect = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        guard cursorRect.isNull == false, cursorRect.isInfinite == false else { return false }
        guard cursorRect.width < 80, cursorRect.height < 80 else { return false }
        return cursorRect.insetBy(dx: -36, dy: -36).contains(boundsPoint)
    }

    /// Bounds-space touch → UTF-16 index.
    /// `closestPosition(to:)` already expects UITextView bounds coords (do not add contentOffset).
    private func utf16Index(atBoundsPoint point: CGPoint) -> Int {
        guard let pos = closestPosition(to: point) else {
            return selectedRange.location
        }
        return offset(from: beginningOfDocument, to: pos)
    }

    @objc private func handleCaretDrag(_ gr: UIPanGestureRecognizer) {
        let boundsPoint = gr.location(in: self)
        switch gr.state {
        case .began:
            draggingCursor = true
            isDraggingCaret = true
            savedTintColor = tintColor
            tintColor = .clear // hide blinking system caret; we draw our own
            if selectMode {
                selectionAnchor = selectedRange.location
            }
            moveCaret(toBoundsPoint: boundsPoint)
            showLoupe(atBoundsPoint: boundsPoint)
        case .changed:
            guard draggingCursor else { return }
            moveCaret(toBoundsPoint: boundsPoint)
            showLoupe(atBoundsPoint: boundsPoint)
        case .ended, .cancelled, .failed:
            if gr.state == .ended {
                moveCaret(toBoundsPoint: boundsPoint)
            }
            draggingCursor = false
            isDraggingCaret = false
            selectionAnchor = nil
            hideLoupe()
            hideDragCaret()
            if let savedTintColor {
                tintColor = savedTintColor
                self.savedTintColor = nil
            }
        default:
            break
        }
    }

    private func moveCaret(toBoundsPoint point: CGPoint) {
        let index = utf16Index(atBoundsPoint: point)
        if selectMode, let anchor = selectionAnchor {
            let start = min(anchor, index)
            let length = abs(anchor - index)
            selectedRange = NSRange(location: start, length: length)
        } else {
            selectedRange = NSRange(location: index, length: 0)
        }
        updateDragCaret(forUTF16Index: index)
    }

    private func updateDragCaret(forUTF16Index index: Int) {
        guard let host = window else { return }
        guard let pos = position(from: beginningOfDocument, offset: index) else { return }
        var rect = caretRect(for: pos)
        if rect.isNull || rect.isInfinite || rect.height < 1 {
            rect = CGRect(x: rect.origin.x, y: rect.origin.y, width: 2, height: font?.lineHeight ?? 18)
        }
        // Widen slightly so it's obvious under a finger.
        rect.size.width = max(2, rect.width)
        let rectInHost = convert(rect, to: host)
        if dragCaret.superview !== host {
            dragCaret.removeFromSuperview()
            host.addSubview(dragCaret)
        }
        dragCaret.isHidden = false
        dragCaret.frame = rectInHost.insetBy(dx: -1, dy: 0)
        host.bringSubviewToFront(dragCaret)
        if loupe.superview === host {
            host.bringSubviewToFront(loupe)
        }
    }

    private func hideDragCaret() {
        dragCaret.isHidden = true
        dragCaret.removeFromSuperview()
    }

    private func showLoupe(atBoundsPoint point: CGPoint) {
        guard let host = window else { return }
        if loupe.superview !== host {
            loupe.removeFromSuperview()
            host.addSubview(loupe)
        }
        loupe.isHidden = false
        host.bringSubviewToFront(loupe)
        let fingerInHost = convert(point, to: host)
        loupe.update(source: self, boundsPoint: point, fingerInHost: fingerInHost)
    }

    private func hideLoupe() {
        loupe.isHidden = true
        loupe.removeFromSuperview()
    }

    /// Remove window-hosted overlays (safe to call from dismantle / navigation).
    func teardownOverlays() {
        hideLoupe()
        hideDragCaret()
        if let savedTintColor {
            tintColor = savedTintColor
            self.savedTintColor = nil
        }
        isDraggingCaret = false
        draggingCursor = false
    }

    override func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard gestureRecognizer === caretDrag else {
            return super.gestureRecognizerShouldBegin(gestureRecognizer)
        }
        if selectMode { return true }
        return isNearCursor(gestureRecognizer.location(in: self))
    }

    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
    ) -> Bool {
        false
    }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if !selectMode {
            if action == #selector(paste(_:)) {
                return super.canPerformAction(action, withSender: sender)
            }
            return false
        }
        return super.canPerformAction(action, withSender: sender)
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

/// Circular magnified snapshot above the finger.
private final class CaretLoupeView: UIView {
    private let imageView = UIImageView()
    private let border = CAShapeLayer()
    private let hairline = UIView()
    private let diameter: CGFloat = 126
    private let magnification: CGFloat = 1.6

    override init(frame: CGRect) {
        super.init(frame: frame)
        bounds = CGRect(x: 0, y: 0, width: diameter, height: diameter)
        isUserInteractionEnabled = false
        backgroundColor = .systemBackground
        layer.cornerRadius = diameter / 2
        clipsToBounds = false

        imageView.contentMode = .scaleToFill
        imageView.clipsToBounds = true
        imageView.layer.cornerRadius = diameter / 2
        imageView.frame = bounds
        addSubview(imageView)

        hairline.backgroundColor = .systemBlue
        hairline.bounds = CGRect(x: 0, y: 0, width: 2, height: diameter * 0.45)
        hairline.center = CGPoint(x: diameter / 2, y: diameter / 2)
        hairline.layer.cornerRadius = 1
        addSubview(hairline)

        border.fillColor = UIColor.clear.cgColor
        border.strokeColor = UIColor.secondaryLabel.cgColor
        border.lineWidth = 2
        border.path = UIBezierPath(ovalIn: bounds.insetBy(dx: 1, dy: 1)).cgPath
        layer.addSublayer(border)

        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.28
        layer.shadowRadius = 8
        layer.shadowOffset = CGSize(width: 0, height: 3)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(source: UITextView, boundsPoint: CGPoint, fingerInHost: CGPoint) {
        let sample = diameter / magnification
        let sampleRect = CGRect(
            x: boundsPoint.x - sample / 2,
            y: boundsPoint.y - sample / 2,
            width: sample,
            height: sample
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = UIScreen.main.scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: diameter, height: diameter), format: format)
        imageView.image = renderer.image { ctx in
            UIColor.systemBackground.setFill()
            ctx.fill(CGRect(origin: .zero, size: CGSize(width: diameter, height: diameter)))
            ctx.cgContext.saveGState()
            ctx.cgContext.translateBy(x: -sampleRect.minX * magnification, y: -sampleRect.minY * magnification)
            ctx.cgContext.scaleBy(x: magnification, y: magnification)
            // Hide loupe from hierarchy snapshot if it were a subview; it's on the window.
            source.drawHierarchy(in: source.bounds, afterScreenUpdates: false)
            ctx.cgContext.restoreGState()
        }

        // Mask to circle.
        let mask = CAShapeLayer()
        mask.path = UIBezierPath(ovalIn: bounds).cgPath
        imageView.layer.mask = mask

        center = CGPoint(x: fingerInHost.x, y: fingerInHost.y - diameter * 0.72)
    }
}

#else

/// macOS package-build stub (iOS app uses the UIKit editor).
struct CodeEditorView: View {
    @Binding var text: String
    var fileKind: EditorInputRules.FileKind
    var filePath: String? = nil
    var restoredScrollY: CGFloat = 0
    var onScrollYChange: ((CGFloat) -> Void)? = nil
    var revealLine: Int? = nil
    var revealColumn: Int? = nil
    var onRevealConsumed: (() -> Void)? = nil

    var body: some View {
        TextEditor(text: $text)
            .font(.system(.body, design: .monospaced))
            .onChange(of: revealLine) { _, line in
                if line != nil { onRevealConsumed?() }
            }
    }
}

#endif
