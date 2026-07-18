import SwiftUI

#if os(iOS)
import UIKit
#endif

/// Run tab: emulator text screen, start/stop, interactive keyboard (DESIGN §7.2 / §6.5).
struct RunTabView: View {
    @ObservedObject var workspace: ProjectWorkspace
    @State private var inputBuffer = ""

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

            ScrollView {
                Text(workspace.screenText.isEmpty ? " " : workspace.screenText)
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .padding(12)
                    .textSelection(.enabled)
            }
            .background(Color.black.opacity(0.05))

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

            #if os(iOS)
            EmulatorKeyboardField(isEnabled: workspace.isRunning) { chars in
                workspace.injectCharacter(chars)
            }
            .frame(height: 1)
            .opacity(0.01)
            #else
            TextField("Type to send keys", text: $inputBuffer)
                .textFieldStyle(.roundedBorder)
                .padding(8)
                .onSubmit {
                    workspace.injectCharacter(inputBuffer + "\n")
                    inputBuffer = ""
                }
                .disabled(!workspace.isRunning)
            #endif
        }
    }
}

#if os(iOS)
/// Hidden field that steals keyboard focus while the emulator runs.
private struct EmulatorKeyboardField: UIViewRepresentable {
    var isEnabled: Bool
    var onCharacters: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onCharacters: onCharacters)
    }

    func makeUIView(context: Context) -> UITextField {
        let field = KeyInterceptField()
        field.delegate = context.coordinator
        field.autocorrectionType = .no
        field.autocapitalizationType = .none
        field.spellCheckingType = .no
        field.smartDashesType = .no
        field.smartQuotesType = .no
        field.smartInsertDeleteType = .no
        field.keyboardType = .asciiCapable
        field.onKey = { [weak coordinator = context.coordinator] text in
            coordinator?.onCharacters(text)
        }
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        context.coordinator.onCharacters = onCharacters
        if isEnabled {
            if !uiView.isFirstResponder {
                uiView.becomeFirstResponder()
            }
        } else if uiView.isFirstResponder {
            uiView.resignFirstResponder()
        }
    }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var onCharacters: (String) -> Void

        init(onCharacters: @escaping (String) -> Void) {
            self.onCharacters = onCharacters
        }

        func textField(
            _ textField: UITextField,
            shouldChangeCharactersIn range: NSRange,
            replacementString string: String
        ) -> Bool {
            if !string.isEmpty {
                onCharacters(string)
            }
            return false
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            onCharacters("\n")
            return false
        }
    }
}

private final class KeyInterceptField: UITextField {
    var onKey: ((String) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func deleteBackward() {
        onKey?("\u{7f}") // DEL; guest may ignore
        super.deleteBackward()
    }
}
#endif
