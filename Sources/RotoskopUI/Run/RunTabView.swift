import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

/// Run tab: emulator text screen, start/stop, interactive keyboard (DESIGN §7.2 / §6.5).
struct RunTabView: View {
    @ObservedObject var workspace: ProjectWorkspace

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button {
                    Task { await workspace.startRun() }
                } label: {
                    Label(workspace.isRunning ? "Restart" : "Run", systemImage: "play.fill")
                }
                .disabled(workspace.isBuilding)

                Button {
                    workspace.stopEmulator()
                } label: {
                    Label("Stop", systemImage: "stop.fill")
                }
                .disabled(!workspace.isRunning)

                Spacer()
                Text(workspace.runStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            ZStack {
                GeometryReader { geo in
                    let horizontalPadding: CGFloat = 12
                    let font = Font(EmulatorScreenFont.make(
                        fittingWidth: max(0, geo.size.width - horizontalPadding * 2)
                    ))
                    ScrollView {
                        screenText
                            .font(font)
                            .frame(maxWidth: .infinity, alignment: .topLeading)
                            .padding(horizontalPadding)
                    }
                }
                .background(Color.black.opacity(0.05))

                #if os(iOS)
                // Full-area first-responder host so the software keyboard stays attached
                // to our intercept field (not the scroll/text views).
                EmulatorKeyboardField(isEnabled: workspace.isRunning) { chars in
                    workspace.injectCharacter(chars)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(workspace.isRunning)
                #endif
            }

            #if os(macOS)
            EmulatorKeyboardField(isEnabled: workspace.isRunning) { chars in
                workspace.injectCharacter(chars)
            }
            .frame(height: 1)
            .opacity(0.01)
            #endif

            if let dump = workspace.registerDump, !workspace.isRunning {
                DisclosureGroup("Registers / stop") {
                    Text(dump)
                        .font(.caption.monospaced())
                        .frame(maxWidth: .infinity, alignment: .leading)
                    if let reason = workspace.stopReasonText {
                        Text(reason).font(.caption).foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
            }
        }
    }

    @ViewBuilder
    private var screenText: some View {
        let content = workspace.screenDisplay == AttributedString()
            ? AttributedString(" ")
            : workspace.screenDisplay
        // Selection steals first responder from the key field while running.
        if workspace.isRunning {
            Text(content)
        } else {
            Text(content).textSelection(.enabled)
        }
    }
}

// MARK: - Per-keystroke capture → $C000 / $C010

#if os(iOS)
/// Invisible `UITextField` that owns the software keyboard and forwards every
/// inserted character (and Delete/Return) into the emulator.
private struct EmulatorKeyboardField: UIViewRepresentable {
    var isEnabled: Bool
    var onCharacters: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCharacters: onCharacters)
    }

    func makeUIView(context: Context) -> KeyInterceptField {
        let field = KeyInterceptField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .asciiCapable
        field.returnKeyType = .default
        field.text = ""
        field.tintColor = .clear
        field.backgroundColor = .clear
        field.isOpaque = false
        context.coordinator.field = field
        field.onKey = { [weak coordinator = context.coordinator] text in
            coordinator?.forward(text)
        }
        return field
    }

    func updateUIView(_ uiView: KeyInterceptField, context: Context) {
        context.coordinator.onCharacters = onCharacters
        context.coordinator.field = uiView
        uiView.onKey = { [weak coordinator = context.coordinator] text in
            coordinator?.forward(text)
        }
        if isEnabled {
            if !uiView.isFirstResponder {
                // Async: becoming first responder during updateUIView is unreliable.
                DispatchQueue.main.async {
                    _ = uiView.becomeFirstResponder()
                }
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onCharacters: (String) -> Void
        weak var field: KeyInterceptField?

        init(onCharacters: @escaping (String) -> Void) {
            self.onCharacters = onCharacters
        }

        func forward(_ string: String) {
            guard !string.isEmpty else { return }
            onCharacters(string)
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            // Primary path for software-keyboard key taps.
            if !string.isEmpty {
                forward(string)
            } else if range.length > 0 {
                // Some delete gestures report as empty replacement + non-zero range.
                forward("\u{7f}")
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            forward("\n")
            return false
        }

        func textFieldShouldBeginEditing(_ textField: UITextField) -> Bool {
            true
        }
    }
}

private final class KeyInterceptField: UITextField {
    var onKey: ((String) -> Void)?

    override var canBecomeFirstResponder: Bool { true }
    override var canResignFirstResponder: Bool { true }

    /// Belt-and-suspenders: some input paths call `insertText` instead of the delegate.
    override func insertText(_ text: String) {
        onKey?(text)
        // Do not call super — keep the field empty.
    }

    override func deleteBackward() {
        onKey?("\u{7f}")
    }

    override func caretRect(for position: UITextPosition) -> CGRect {
        .zero
    }

    override func selectionRects(for range: UITextRange) -> [UITextSelectionRect] {
        []
    }
}

#elseif os(macOS)
/// Local key monitor while running — delivers every keystroke to `$C000`, not only on Return.
private struct EmulatorKeyboardField: NSViewRepresentable {
    var isEnabled: Bool
    var onCharacters: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCharacters: onCharacters)
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        context.coordinator.attach(onCharacters: onCharacters)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.onCharacters = onCharacters
        context.coordinator.setEnabled(isEnabled)
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.setEnabled(false)
    }

    final class Coordinator {
        var onCharacters: (String) -> Void
        private var monitor: Any?

        init(onCharacters: @escaping (String) -> Void) {
            self.onCharacters = onCharacters
        }

        func attach(onCharacters: @escaping (String) -> Void) {
            self.onCharacters = onCharacters
        }

        func setEnabled(_ enabled: Bool) {
            if enabled {
                guard monitor == nil else { return }
                monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                    guard let self else { return event }
                    if self.handle(event) {
                        return nil // consume
                    }
                    return event
                }
            } else if let monitor {
                NSEvent.removeMonitor(monitor)
                self.monitor = nil
            }
        }

        /// Returns true if the event was forwarded to the emulator.
        private func handle(_ event: NSEvent) -> Bool {
            // Leave menu shortcuts (⌘S, etc.) alone.
            if event.modifierFlags.contains(.command) {
                return false
            }
            switch event.keyCode {
            case 36, 76: // Return / keypad Enter
                onCharacters("\n")
                return true
            case 51: // Delete
                onCharacters("\u{7f}")
                return true
            case 53: // Escape
                onCharacters("\u{1b}")
                return true
            case 123: // Left → BS
                onCharacters("\u{08}")
                return true
            case 124: // Right
                onCharacters("\u{15}")
                return true
            case 125: // Down
                onCharacters("\u{0a}")
                return true
            case 126: // Up
                onCharacters("\u{0b}")
                return true
            default:
                if let chars = event.characters, !chars.isEmpty {
                    onCharacters(chars)
                    return true
                }
                return false
            }
        }

        deinit {
            setEnabled(false)
        }
    }
}
#endif
