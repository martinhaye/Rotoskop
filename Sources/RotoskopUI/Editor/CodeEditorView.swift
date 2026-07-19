import SwiftUI

#if os(iOS)
import UIKit

/// Disarmed UITextView editor with Space/Tab/Enter rules and simple highlighting (DESIGN §3).
///
/// Horizontal scroll is owned by an outer `UIScrollView`; the text view is sized to the
/// full document and does not scroll itself (UITextView H-scroll reliably blanks glyphs).
struct CodeEditorView: UIViewRepresentable {
    @Binding var text: String
    var fileKind: EditorInputRules.FileKind
    var filePath: String?
    var restoredScrollOffset: CGPoint
    var onScrollOffsetChange: ((CGPoint) -> Void)?
    var revealLine: Int?
    var revealColumn: Int?
    var onRevealConsumed: (() -> Void)?

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIView(context: Context) -> EditorScrollContainer {
        let container = EditorScrollContainer()
        let view = container.editor
        view.delegate = context.coordinator
        container.delegate = context.coordinator
        view.backgroundColor = .systemBackground
        container.backgroundColor = .systemBackground
        view.textContainer.lineFragmentPadding = 8
        view.textContainerInset = UIEdgeInsets(top: 8, left: 0, bottom: 8, right: 0)
        view.textContainer.widthTracksTextView = false
        view.textContainer.heightTracksTextView = false
        // Critical for SwiftUI: don't hug content or the host grows with the document.
        container.setContentHuggingPriority(.defaultLow, for: .vertical)
        container.setContentHuggingPriority(.defaultLow, for: .horizontal)
        container.setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        container.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
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
        context.coordinator.installKeyboard(on: view)
        context.coordinator.applyAttributedText(to: view, string: text, forceCursor: nil)
        context.coordinator.trackedPath = filePath
        context.coordinator.restoreScroll(restoredScrollOffset, in: container)
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
        context.coordinator.scrollContainer = container
        return container
    }

    func updateUIView(_ uiView: EditorScrollContainer, context: Context) {
        context.coordinator.parent = self
        context.coordinator.editor = uiView.editor
        context.coordinator.scrollContainer = uiView
        uiView.editor.fileKind = fileKind
        context.coordinator.installKeyboard(on: uiView.editor)

        let pathChanged = context.coordinator.trackedPath != filePath
        if pathChanged {
            context.coordinator.trackedPath = filePath
            uiView.editor.resetTrackedLine()
            context.coordinator.applyAttributedText(to: uiView.editor, string: text, forceCursor: NSRange(location: 0, length: 0))
            context.coordinator.restoreScroll(restoredScrollOffset, in: uiView)
        } else if uiView.editor.markedTextRange == nil, uiView.editor.text != text {
            let selected = uiView.editor.selectedRange
            context.coordinator.applyAttributedText(to: uiView.editor, string: text, forceCursor: selected)
        }

        if let line = revealLine {
            context.coordinator.reveal(line: line, column: revealColumn ?? 1, in: uiView.editor)
            DispatchQueue.main.async {
                onRevealConsumed?()
            }
        }
    }

    static func dismantleUIView(_ uiView: EditorScrollContainer, coordinator: Coordinator) {
        coordinator.parent.onScrollOffsetChange?(uiView.contentOffset)
        uiView.editor.teardownOverlays()
        NotificationCenter.default.removeObserver(coordinator)
        coordinator.editor = nil
        coordinator.scrollContainer = nil
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIScrollViewDelegate {
        var parent: CodeEditorView
        weak var editor: EditorTextView?
        weak var scrollContainer: EditorScrollContainer?
        var trackedPath: String?
        var isApplyingHighlight = false
        private var suppressScrollCallback = false
        private var keyboard: AssemblyKeyboardView?

        init(_ parent: CodeEditorView) {
            self.parent = parent
        }

        func installKeyboard(on textView: EditorTextView) {
            if keyboard == nil {
                keyboard = AssemblyKeyboard.install(
                    on: textView,
                    insert: { [weak self] text in
                        self?.editor?.insertText(text)
                    },
                    delete: { [weak self] in
                        self?.editor?.deleteBackward()
                    }
                )
            } else if textView.inputView !== keyboard {
                textView.inputView = keyboard
                textView.inputAccessoryView = nil
                if textView.isFirstResponder {
                    textView.reloadInputViews()
                }
            }
        }

        @objc func handleSelectNotification() {
            editor?.enterSelectMode()
        }

        @objc func handleSelectAllNotification() {
            editor?.selectAll(nil)
            editor?.enterSelectMode()
        }

        func restoreScroll(_ offset: CGPoint, in container: EditorScrollContainer) {
            suppressScrollCallback = true
            container.setNeedsLayout()
            container.layoutIfNeeded()
            let clamped = Self.clampedContentOffset(offset, in: container)
            container.setContentOffset(clamped, animated: false)
            DispatchQueue.main.async { [weak self, weak container] in
                guard let self, let container else { return }
                container.setNeedsLayout()
                container.layoutIfNeeded()
                container.setContentOffset(Self.clampedContentOffset(offset, in: container), animated: false)
                container.editor.syncTrackedLineWithoutScrolling()
                self.suppressScrollCallback = false
            }
        }

        private static func clampedContentOffset(_ offset: CGPoint, in scrollView: UIScrollView) -> CGPoint {
            let maxX = max(0, scrollView.contentSize.width - scrollView.bounds.width)
            let maxY = max(0, scrollView.contentSize.height - scrollView.bounds.height)
            return CGPoint(
                x: min(max(0, offset.x), maxX),
                y: min(max(0, offset.y), maxY)
            )
        }

        func scrollViewDidScroll(_ scrollView: UIScrollView) {
            guard !suppressScrollCallback else { return }
            parent.onScrollOffsetChange?(scrollView.contentOffset)
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
            if let editor = textView as? EditorTextView {
                editor.scrollHorizontallyPreferringLeadingEdge(forceLineTracking: true)
            }
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
            guard !isApplyingHighlight, let editor = textView as? EditorTextView else { return }

            if !editor.selectMode, !editor.isDraggingCaret, editor.selectedRange.length > 0 {
                // Tap / double-tap must only move the caret unless ⋯ Select mode is on (DESIGN §3.6).
                let caret = editor.selectedRange.location + editor.selectedRange.length
                editor.selectedRange = NSRange(location: caret, length: 0)
                return
            }

            // Prefer scrolling X back toward 0 when the caret changes lines (skip during drag).
            if !editor.isDraggingCaret {
                editor.scrollHorizontallyIfLineChanged()
            }
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
            let font = EditorCodingFont.make()
            let attributed = AssemblyHighlighter.attributedString(
                for: string,
                font: font,
                isAssembly: parent.fileKind == .assembly
            )
            textView.font = font
            textView.attributedText = attributed
            if let editor = textView as? EditorTextView {
                editor.relayoutContentSize()
            }
            if let forceCursor {
                let maxLoc = (textView.text as NSString?)?.length ?? 0
                let loc = min(forceCursor.location, maxLoc)
                let len = min(forceCursor.length, max(0, maxLoc - loc))
                textView.selectedRange = NSRange(location: loc, length: len)
            }
            isApplyingHighlight = false
            // Enter / edits can change lines while highlight suppresses selection callbacks.
            if let editor = textView as? EditorTextView, !editor.isDraggingCaret {
                editor.scrollHorizontallyIfLineChanged()
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

/// Outer scroller; hosts a non-scrolling `EditorTextView` sized to the full document.
final class EditorScrollContainer: UIScrollView {
    let editor: EditorTextView

    override init(frame: CGRect) {
        editor = EditorTextView(frame: .zero)
        super.init(frame: frame)
        alwaysBounceVertical = true
        alwaysBounceHorizontal = true
        isDirectionalLockEnabled = true
        keyboardDismissMode = .interactive
        contentInsetAdjustmentBehavior = .automatic
        editor.isScrollEnabled = false
        addSubview(editor)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let size = editor.fitContent(viewport: bounds.size)
        if editor.frame.origin != .zero || abs(editor.frame.width - size.width) > 0.5
            || abs(editor.frame.height - size.height) > 0.5 {
            editor.frame = CGRect(origin: .zero, size: size)
        }
        if abs(contentSize.width - size.width) > 0.5 || abs(contentSize.height - size.height) > 0.5 {
            contentSize = size
        }
    }
}

/// UITextView with select-mode, near-caret pan to move caret, and a simple loupe (DESIGN §3.6).
/// Scrolling is owned by `EditorScrollContainer` — this view is sized to the document.
final class EditorTextView: UITextView, UIGestureRecognizerDelegate {
    var fileKind: EditorInputRules.FileKind = .plain
    private(set) var selectMode = false
    private var draggingCursor = false
    private var selectionAnchor: Int?
    private weak var caretDrag: UIPanGestureRecognizer?
    private var edgeScrollLink: CADisplayLink?
    /// Prevents `fitContent` from re-entering via layout.
    private var isFittingContent = false
    /// UTF-16 start of the line last used for prefer-left horizontal scroll.
    private var trackedLineStart: Int = -1
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

    private var hostScrollView: UIScrollView? {
        superview as? UIScrollView
    }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: UIView.noIntrinsicMetric)
    }

    override init(frame: CGRect, textContainer: NSTextContainer?) {
        super.init(frame: frame, textContainer: textContainer)
        // Pan (not long-press): began/changed fire immediately. shouldBegin limits it to
        // near-caret so the outer scroll view still wins for far pans.
        let drag = UIPanGestureRecognizer(target: self, action: #selector(handleCaretDrag(_:)))
        drag.delegate = self
        drag.maximumNumberOfTouches = 1
        addGestureRecognizer(drag)
        caretDrag = drag
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
    }

    /// Ask the host scroll container to re-measure after text changes.
    func relayoutContentSize() {
        guard let scroll = hostScrollView else { return }
        scroll.setNeedsLayout()
        scroll.layoutIfNeeded()
    }

    /// Size this view (and its text container) to the wider of the viewport and the
    /// longest line so the outer scroll view can pan over real glyphs (DESIGN §3.2).
    @discardableResult
    func fitContent(viewport: CGSize) -> CGSize {
        guard viewport.width > 1, !isFittingContent else {
            return bounds.size.width > 1 ? bounds.size : viewport
        }
        isFittingContent = true
        defer { isFittingContent = false }

        textContainer.widthTracksTextView = false
        textContainer.heightTracksTextView = false

        let unconstrained = CGSize(
            width: CGFloat.greatestFiniteMagnitude,
            height: CGFloat.greatestFiniteMagnitude
        )
        textContainer.size = unconstrained

        let fullRange = NSRange(location: 0, length: textStorage.length)
        if fullRange.length > 0 {
            layoutManager.invalidateLayout(forCharacterRange: fullRange, actualCharacterRange: nil)
        }
        layoutManager.ensureLayout(for: textContainer)
        let used = layoutManager.usedRect(for: textContainer)

        // Trailing slack keeps the caret from sitting flush against the clip edge.
        let trailingSlack = textContainer.lineFragmentPadding + 24
        let width = max(viewport.width, ceil(used.maxX) + trailingSlack)
        let height = max(
            viewport.height,
            ceil(used.maxY) + textContainerInset.top + textContainerInset.bottom
        )

        textContainer.size = CGSize(width: width, height: height)
        layoutManager.ensureLayout(for: textContainer)
        return CGSize(width: width, height: height)
    }

    func resetTrackedLine() {
        trackedLineStart = -1
    }

    func syncTrackedLineWithoutScrolling() {
        trackedLineStart = currentLineStartUTF16()
    }

    /// When the caret moves to another line, prefer scrolling X back toward 0.
    func scrollHorizontallyIfLineChanged() {
        let lineStart = currentLineStartUTF16()
        if trackedLineStart < 0 {
            trackedLineStart = lineStart
            return
        }
        guard lineStart != trackedLineStart else { return }
        scrollHorizontallyPreferringLeadingEdge(forceLineTracking: true)
    }

    /// Scroll the host scroller's X as far left as possible while keeping the caret
    /// visible; if the whole line fits, snap to x = 0 (DESIGN §3.6).
    func scrollHorizontallyPreferringLeadingEdge(forceLineTracking: Bool = false) {
        if forceLineTracking {
            trackedLineStart = currentLineStartUTF16()
        }
        relayoutContentSize()
        guard let scroll = hostScrollView else { return }

        let ns = text as NSString? ?? ""
        let caretIndex = max(0, min(selectedRange.location, ns.length))
        let lineRange = lineCharacterRange(containingUTF16: caretIndex)
        let lineRect = contentRect(forCharacterRange: lineRange)
        let caret = caretContentRect(atUTF16: caretIndex)

        let visibleWidth = scroll.bounds.width
        let visibleHeight = scroll.bounds.height
        let margin: CGFloat = 24
        let maxOffsetX = max(0, scroll.contentSize.width - visibleWidth)
        let maxOffsetY = max(0, scroll.contentSize.height - visibleHeight)

        var offset = scroll.contentOffset

        // Keep caret vertically in view when jumping (e.g. diagnostic reveal).
        if caret.minY < offset.y {
            offset.y = max(0, caret.minY - margin)
        } else if caret.maxY > offset.y + visibleHeight {
            offset.y = min(maxOffsetY, caret.maxY + margin - visibleHeight)
        }

        if lineRect.maxX <= visibleWidth {
            offset.x = 0
        } else {
            offset.x = min(maxOffsetX, max(0, caret.maxX + margin - visibleWidth))
        }

        offset.x = min(max(0, offset.x), maxOffsetX)
        offset.y = min(max(0, offset.y), maxOffsetY)
        guard abs(scroll.contentOffset.x - offset.x) > 0.5
            || abs(scroll.contentOffset.y - offset.y) > 0.5
        else { return }
        scroll.setContentOffset(offset, animated: false)
    }

    private func currentLineStartUTF16() -> Int {
        lineCharacterRange(containingUTF16: selectedRange.location).location
    }

    private func lineCharacterRange(containingUTF16 location: Int) -> NSRange {
        let ns = text as NSString? ?? ""
        guard ns.length > 0 else { return NSRange(location: 0, length: 0) }
        if location >= ns.length {
            // Caret at end of document: if the last char is a newline, we're on a new empty line.
            if ns.character(at: ns.length - 1) == 10 {
                return NSRange(location: ns.length, length: 0)
            }
            var lineStart = 0
            var lineEnd = 0
            var contentsEnd = 0
            ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: ns.length - 1, length: 0))
            return NSRange(location: lineStart, length: contentsEnd - lineStart)
        }
        var lineStart = 0
        var lineEnd = 0
        var contentsEnd = 0
        ns.getLineStart(&lineStart, end: &lineEnd, contentsEnd: &contentsEnd, for: NSRange(location: location, length: 0))
        return NSRange(location: lineStart, length: contentsEnd - lineStart)
    }

    private func contentRect(forCharacterRange range: NSRange) -> CGRect {
        guard range.length > 0 else {
            let originX = textContainerInset.left + textContainer.lineFragmentPadding
            return CGRect(x: originX, y: textContainerInset.top, width: 0, height: font?.lineHeight ?? 18)
        }
        let glyphRange = layoutManager.glyphRange(forCharacterRange: range, actualCharacterRange: nil)
        var rect = layoutManager.boundingRect(forGlyphRange: glyphRange, in: textContainer)
        rect.origin.x += textContainerInset.left
        rect.origin.y += textContainerInset.top
        return rect
    }

    private func caretContentRect(atUTF16 index: Int) -> CGRect {
        let ns = text as NSString? ?? ""
        let safe = max(0, min(index, ns.length))
        guard let pos = position(from: beginningOfDocument, offset: safe) else {
            let originX = textContainerInset.left + textContainer.lineFragmentPadding
            return CGRect(x: originX, y: textContainerInset.top, width: 2, height: font?.lineHeight ?? 18)
        }
        var rect = caretRect(for: pos)
        if rect.isNull || rect.isInfinite || rect.height < 1 {
            rect = CGRect(x: rect.origin.x, y: rect.origin.y, width: 2, height: font?.lineHeight ?? 18)
        }
        return rect
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

    private func isNearCursor(_ contentPoint: CGPoint) -> Bool {
        let cursorRect = caretRect(for: selectedTextRange?.start ?? beginningOfDocument)
        guard cursorRect.isNull == false, cursorRect.isInfinite == false else { return false }
        guard cursorRect.width < 80, cursorRect.height < 80 else { return false }
        return cursorRect.insetBy(dx: -36, dy: -36).contains(contentPoint)
    }

    /// True when the point is near the caret or any selection fragment (text-view space).
    private func isNearEditableHotspot(_ contentPoint: CGPoint) -> Bool {
        if isNearCursor(contentPoint) { return true }
        guard selectedRange.length > 0,
              let start = position(from: beginningOfDocument, offset: selectedRange.location),
              let end = position(from: beginningOfDocument, offset: selectedRange.location + selectedRange.length),
              let range = textRange(from: start, to: end)
        else { return false }
        for selectionRect in selectionRects(for: range) {
            if selectionRect.rect.insetBy(dx: -36, dy: -36).contains(contentPoint) {
                return true
            }
        }
        return false
    }

    /// Text-view coordinates → UTF-16 index (view is not itself scrolled).
    private func utf16Index(atContentPoint point: CGPoint) -> Int {
        guard let pos = closestPosition(to: point) else {
            return selectedRange.location
        }
        return offset(from: beginningOfDocument, to: pos)
    }

    @objc private func handleCaretDrag(_ gr: UIPanGestureRecognizer) {
        let contentPoint = gr.location(in: self)
        switch gr.state {
        case .began:
            draggingCursor = true
            isDraggingCaret = true
            savedTintColor = tintColor
            tintColor = .clear // hide blinking system caret; we draw our own
            if selectMode {
                selectionAnchor = selectedRange.location
            }
            moveCaret(toContentPoint: contentPoint)
            showLoupe(atContentPoint: contentPoint)
            startEdgeScroll()
        case .changed:
            guard draggingCursor else { return }
            _ = autoScrollTowardEdges(fingerInTextView: contentPoint)
            moveCaret(toContentPoint: gr.location(in: self))
            showLoupe(atContentPoint: gr.location(in: self))
        case .ended, .cancelled, .failed:
            stopEdgeScroll()
            if gr.state == .ended {
                moveCaret(toContentPoint: contentPoint)
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
            // After drag, snap X toward leading if we landed on a different line.
            if gr.state == .ended {
                scrollHorizontallyIfLineChanged()
            }
        default:
            break
        }
    }

    private func startEdgeScroll() {
        stopEdgeScroll()
        let link = CADisplayLink(target: self, selector: #selector(edgeScrollTick))
        link.add(to: .main, forMode: .common)
        edgeScrollLink = link
    }

    private func stopEdgeScroll() {
        edgeScrollLink?.invalidate()
        edgeScrollLink = nil
    }

    @objc private func edgeScrollTick() {
        guard draggingCursor, let gr = caretDrag, gr.state == .changed || gr.state == .began else { return }
        let point = gr.location(in: self)
        guard autoScrollTowardEdges(fingerInTextView: point) else { return }
        // After scrolling, re-sample so caret tracks the content under the finger.
        let updated = gr.location(in: self)
        moveCaret(toContentPoint: updated)
        showLoupe(atContentPoint: updated)
    }

    /// When the finger sits near a visible edge of the host scroller, nudge its offset.
    @discardableResult
    private func autoScrollTowardEdges(fingerInTextView: CGPoint) -> Bool {
        guard let scroll = hostScrollView else { return false }
        let finger = convert(fingerInTextView, to: scroll)
        let margin: CGFloat = 44
        let step: CGFloat = 10
        var offset = scroll.contentOffset
        let maxX = max(0, scroll.contentSize.width - scroll.bounds.width)
        let maxY = max(0, scroll.contentSize.height - scroll.bounds.height)
        let visible = scroll.bounds

        if finger.x > visible.maxX - margin {
            offset.x = min(maxX, offset.x + step)
        } else if finger.x < visible.minX + margin {
            offset.x = max(0, offset.x - step)
        }
        if finger.y > visible.maxY - margin {
            offset.y = min(maxY, offset.y + step)
        } else if finger.y < visible.minY + margin {
            offset.y = max(0, offset.y - step)
        }

        guard offset != scroll.contentOffset else { return false }
        scroll.setContentOffset(offset, animated: false)
        return true
    }

    private func moveCaret(toContentPoint point: CGPoint) {
        let index = utf16Index(atContentPoint: point)
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

    private func showLoupe(atContentPoint point: CGPoint) {
        guard let host = window else { return }
        if loupe.superview !== host {
            loupe.removeFromSuperview()
            host.addSubview(loupe)
        }
        loupe.isHidden = false
        host.bringSubviewToFront(loupe)
        let fingerInHost = convert(point, to: host)
        loupe.update(source: self, contentPoint: point, fingerInHost: fingerInHost)
    }

    private func hideLoupe() {
        loupe.isHidden = true
        loupe.removeFromSuperview()
    }

    /// Remove window-hosted overlays (safe to call from dismantle / navigation).
    func teardownOverlays() {
        stopEdgeScroll()
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
        // Far pans must scroll — even in select mode (DESIGN §3.6).
        return isNearEditableHotspot(gestureRecognizer.location(in: self))
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

    func update(source: UITextView, contentPoint: CGPoint, fingerInHost: CGPoint) {
        let sample = diameter / magnification
        let sampleRect = CGRect(
            x: contentPoint.x - sample / 2,
            y: contentPoint.y - sample / 2,
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
            // Text view is not scrolled; bounds.origin is zero and matches contentPoint.
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
    var restoredScrollOffset: CGPoint = .zero
    var onScrollOffsetChange: ((CGPoint) -> Void)? = nil
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
