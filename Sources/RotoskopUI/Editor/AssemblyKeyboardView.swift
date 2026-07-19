#if os(iOS)
import UIKit

/// App-local software keyboard tuned for Apple II assembly editing.
///
/// Replaces the system keyboard via `inputView` so we control symbol placement
/// (e.g. `# + =` on the first symbols page) and omit emoji / dictation chrome.
final class AssemblyKeyboardView: UIInputView {
    var onInsert: ((String) -> Void)?
    var onDelete: (() -> Void)?

    private enum Page {
        case letters
        case symbols
    }

    private var page: Page = .letters {
        didSet { rebuild() }
    }

    /// Shift applies to the next letter only (unless caps lock).
    private var shiftOnce = false {
        didSet { refreshLetterCase() }
    }

    private var capsLock = false {
        didSet { refreshLetterCase() }
    }

    private let rootStack = UIStackView()
    private var letterButtons: [KeyButton] = []
    private var suggestionButtons: [KeyButton] = []
    private var currentSuggestions: [String] = AssemblyKeyboardSuggestions.baseline
    private var shiftButton: KeyButton?
    private var deleteRepeatTimer: Timer?
    private var deleteRepeatCount = 0

    private static let keyboardHeight: CGFloat = 278

    init() {
        super.init(
            frame: CGRect(x: 0, y: 0, width: 320, height: Self.keyboardHeight),
            inputViewStyle: .keyboard
        )
        autoresizingMask = .flexibleWidth
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.17, alpha: 1)
                : UIColor(red: 0.82, green: 0.84, blue: 0.86, alpha: 1)
        }
        rootStack.axis = .vertical
        rootStack.spacing = 10
        rootStack.alignment = .fill
        rootStack.distribution = .fillEqually
        rootStack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rootStack)
        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 4),
            rootStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -4),
            rootStack.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            rootStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -8),
        ])
        rebuild()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func willMove(toWindow newWindow: UIWindow?) {
        super.willMove(toWindow: newWindow)
        if newWindow == nil {
            deleteRepeatTimer?.invalidate()
            deleteRepeatTimer = nil
        }
    }

    /// Refresh the letters-page suggestion row from text before the caret.
    func updateSuggestions(beforeCaret: String) {
        let next = AssemblyKeyboardSuggestions.symbols(beforeCaret: beforeCaret)
        guard next != currentSuggestions else { return }
        currentSuggestions = next
        applySuggestionTitles()
    }

    // MARK: - Layout

    private func rebuild() {
        rootStack.arrangedSubviews.forEach { $0.removeFromSuperview() }
        letterButtons.removeAll()
        suggestionButtons.removeAll()
        shiftButton = nil

        switch page {
        case .letters:
            buildLetters()
        case .symbols:
            buildSymbols()
        }
    }

    private func buildLetters() {
        addSuggestionRow(currentSuggestions)
        addRow(["Q", "W", "E", "R", "T", "Y", "U", "I", "O", "P"], letterRow: true)
        addRow(["A", "S", "D", "F", "G", "H", "J", "K", "L"], letterRow: true, inset: 16)
        addLetterBottomLetterRow()
        addUtilityRow(modeTitle: "123")
        refreshLetterCase()
    }

    private func addSuggestionRow(_ titles: [String]) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        row.alignment = .fill
        for title in titles {
            let key = makeCharKey(title, letterRow: false)
            suggestionButtons.append(key)
            row.addArrangedSubview(key)
        }
        rootStack.addArrangedSubview(row)
    }

    private func applySuggestionTitles() {
        guard page == .letters else { return }
        // Rebuild the row if the count ever drifts; normally we only retitle in place.
        if suggestionButtons.count != currentSuggestions.count {
            if page == .letters { rebuild() }
            return
        }
        for (button, title) in zip(suggestionButtons, currentSuggestions) {
            button.setTitle(title, for: .normal)
        }
    }

    private func buildSymbols() {
        // Digits + ASM-first symbols (no second page for # + =).
        addRow(["1", "2", "3", "4", "5", "6", "7", "8", "9", "0"])
        addRow(["#", "$", "+", "=", "%", "\"", "'", "<", ">"])
        addRow([":", ";", "*", "(", ")", "[", "]", "!", "?", "_"])
        addSymbolsBottomRow()
        addUtilityRow(modeTitle: "ABC")
    }

    private func addLetterBottomLetterRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill
        row.alignment = .fill

        let shift = makeSpecialKey(title: "⇧", width: 44) { [weak self] in
            self?.toggleShift()
        }
        shiftButton = shift
        row.addArrangedSubview(shift)

        let letters = UIStackView()
        letters.axis = .horizontal
        letters.spacing = 6
        letters.distribution = .fillEqually
        letters.alignment = .fill
        letters.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for letter in ["Z", "X", "C", "V", "B", "N", "M"] {
            letters.addArrangedSubview(makeCharKey(letter, letterRow: true))
        }
        row.addArrangedSubview(letters)

        let del = makeSpecialKey(title: "⌫", width: 44) {}
        configureDelete(del)
        row.addArrangedSubview(del)

        rootStack.addArrangedSubview(row)
    }

    private func addSymbolsBottomRow() {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill
        row.alignment = .fill

        let symbols = UIStackView()
        symbols.axis = .horizontal
        symbols.spacing = 6
        symbols.distribution = .fillEqually
        symbols.alignment = .fill
        symbols.setContentHuggingPriority(.defaultLow, for: .horizontal)
        for symbol in ["-", "/", "\\", "@", "&", "^", "~", ",", "."] {
            symbols.addArrangedSubview(makeCharKey(symbol, letterRow: false))
        }
        row.addArrangedSubview(symbols)

        let del = makeSpecialKey(title: "⌫", width: 44) {}
        configureDelete(del)
        row.addArrangedSubview(del)

        rootStack.addArrangedSubview(row)
    }

    private func addUtilityRow(modeTitle: String) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fill
        row.alignment = .fill

        row.addArrangedSubview(makeSpecialKey(title: modeTitle, width: 52) { [weak self] in
            guard let self else { return }
            self.page = self.page == .letters ? .symbols : .letters
            self.shiftOnce = false
            self.capsLock = false
        })

        row.addArrangedSubview(makeSpecialKey(title: "tab", width: 44) { [weak self] in
            self?.onInsert?("\t")
        })

        let space = makeSpecialKey(title: "space", width: 0) { [weak self] in
            self?.onInsert?(" ")
        }
        space.setContentHuggingPriority(.defaultLow, for: .horizontal)
        row.addArrangedSubview(space)

        row.addArrangedSubview(makeSpecialKey(title: "return", width: 72) { [weak self] in
            self?.onInsert?("\n")
        })

        rootStack.addArrangedSubview(row)
    }

    private func addRow(_ titles: [String], letterRow: Bool = false, inset: CGFloat = 0) {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = 6
        row.distribution = .fillEqually
        row.alignment = .fill
        row.isLayoutMarginsRelativeArrangement = inset > 0
        if inset > 0 {
            row.layoutMargins = UIEdgeInsets(top: 0, left: inset, bottom: 0, right: inset)
        }
        for title in titles {
            row.addArrangedSubview(makeCharKey(title, letterRow: letterRow))
        }
        rootStack.addArrangedSubview(row)
    }

    // MARK: - Keys

    private func makeCharKey(_ title: String, letterRow: Bool) -> KeyButton {
        let key = KeyButton(style: .character)
        key.setTitle(title, for: .normal)
        key.tapHandler = { [weak self, weak key] in
            guard let self, let text = key?.title(for: .normal) ?? key?.currentTitle else { return }
            self.onInsert?(text)
            if self.page == .letters, self.shiftOnce, !self.capsLock {
                self.shiftOnce = false
            }
        }
        key.addTarget(self, action: #selector(specialKeyTapped(_:)), for: .touchUpInside)
        if letterRow {
            letterButtons.append(key)
        }
        return key
    }

    private func makeSpecialKey(title: String, width: CGFloat, action: @escaping () -> Void) -> KeyButton {
        let key = KeyButton(style: .special)
        key.setTitle(title, for: .normal)
        if width > 0 {
            key.widthAnchor.constraint(equalToConstant: width).isActive = true
        }
        key.tapHandler = action
        key.addTarget(self, action: #selector(specialKeyTapped(_:)), for: .touchUpInside)
        return key
    }

    @objc private func specialKeyTapped(_ sender: KeyButton) {
        sender.tapHandler?()
    }

    private func configureDelete(_ key: KeyButton) {
        key.addTarget(self, action: #selector(deleteTouchDown), for: .touchDown)
        key.addTarget(self, action: #selector(deleteTouchEnd), for: [.touchUpInside, .touchUpOutside, .touchCancel])
    }

    @objc private func deleteTouchDown() {
        onDelete?()
        deleteRepeatCount = 0
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: false) { [weak self] _ in
            self?.startDeleteRepeat()
        }
    }

    private func startDeleteRepeat() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = Timer.scheduledTimer(withTimeInterval: 0.07, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.onDelete?()
            self.deleteRepeatCount += 1
        }
    }

    @objc private func deleteTouchEnd() {
        deleteRepeatTimer?.invalidate()
        deleteRepeatTimer = nil
    }

    private var lastShiftTap = CACurrentMediaTime()

    private func toggleShift() {
        let now = CACurrentMediaTime()
        if now - lastShiftTap < 0.35 {
            capsLock = true
            shiftOnce = false
        } else if capsLock {
            capsLock = false
            shiftOnce = false
        } else if shiftOnce {
            shiftOnce = false
        } else {
            shiftOnce = true
        }
        lastShiftTap = now
    }

    private func refreshLetterCase() {
        let upper = capsLock || shiftOnce
        for button in letterButtons {
            guard let title = button.currentTitle ?? button.title(for: .normal) else { continue }
            button.setTitle(upper ? title.uppercased() : title.lowercased(), for: .normal)
        }
        shiftButton?.isHighlightedStyle = upper
    }
}

// MARK: - Key button

private final class KeyButton: UIButton {
    enum Style {
        case character
        case special
    }

    var tapHandler: (() -> Void)?
    var isHighlightedStyle = false {
        didSet { applyColors() }
    }

    private let keyStyle: Style

    init(style: Style) {
        self.keyStyle = style
        super.init(frame: .zero)
        titleLabel?.font = .systemFont(ofSize: style == .special ? 15 : 22, weight: .regular)
        titleLabel?.adjustsFontSizeToFitWidth = true
        layer.cornerRadius = 5
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.25
        layer.shadowRadius = 0
        layer.shadowOffset = CGSize(width: 0, height: 1)
        addTarget(self, action: #selector(touchDown), for: .touchDown)
        addTarget(self, action: #selector(touchUp), for: [.touchUpInside, .touchUpOutside, .touchCancel])
        applyColors()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 42)
    }

    @objc private func touchDown() {
        backgroundColor = UIColor { traits in
            traits.userInterfaceStyle == .dark
                ? UIColor(white: 0.55, alpha: 1)
                : UIColor(white: 0.75, alpha: 1)
        }
    }

    @objc private func touchUp() {
        applyColors()
    }

    private func applyColors() {
        let dark = traitCollection.userInterfaceStyle == .dark
        switch keyStyle {
        case .character:
            backgroundColor = dark ? UIColor(white: 0.40, alpha: 1) : .white
            setTitleColor(dark ? .white : .black, for: .normal)
        case .special:
            if isHighlightedStyle {
                backgroundColor = dark ? UIColor(white: 0.85, alpha: 1) : .white
                setTitleColor(.black, for: .normal)
            } else {
                backgroundColor = dark ? UIColor(white: 0.28, alpha: 1) : UIColor(red: 0.68, green: 0.71, blue: 0.74, alpha: 1)
                setTitleColor(dark ? .white : .black, for: .normal)
            }
        }
    }

    override func traitCollectionDidChange(_ previousTraitCollection: UITraitCollection?) {
        super.traitCollectionDidChange(previousTraitCollection)
        applyColors()
    }
}

// MARK: - Attachment helper

enum AssemblyKeyboard {
    /// Installs the custom keyboard as `inputView` and clears any accessory strip.
    @MainActor
    static func install(
        on textInput: UITextInput & UIResponder,
        insert: @escaping (String) -> Void,
        delete: @escaping () -> Void
    ) -> AssemblyKeyboardView {
        let keyboard = AssemblyKeyboardView()
        keyboard.onInsert = insert
        keyboard.onDelete = delete
        if let field = textInput as? UITextField {
            field.inputView = keyboard
            field.inputAccessoryView = nil
            if field.isFirstResponder { field.reloadInputViews() }
        } else if let view = textInput as? UITextView {
            view.inputView = keyboard
            view.inputAccessoryView = nil
            if view.isFirstResponder { view.reloadInputViews() }
        }
        return keyboard
    }
}
#endif
