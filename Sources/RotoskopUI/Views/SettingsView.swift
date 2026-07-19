import SwiftUI

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @State private var token = ""
    @State private var statusMessage: String?

    var body: some View {
        Form {
            Section {
                tokenField
                Button("Save Token") {
                    do {
                        try model.savePAT(token)
                        token = ""
                        statusMessage = "Token saved to Keychain."
                    } catch {
                        statusMessage = error.localizedDescription
                    }
                }
                if model.hasPAT {
                    Button("Clear Token", role: .destructive) {
                        do {
                            try model.clearPAT()
                            statusMessage = "Token cleared."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                }
            } header: {
                Text("GitHub Auth")
            } footer: {
                Text("v1 uses a classic or fine-grained PAT with repo access. Stored in Keychain; used for HTTPS clone, push, and pull.")
            }

            Section {
                HStack {
                    Text("Clock")
                    Spacer()
                    Text(EmulationPreferences.formatMHz(model.clockMHz))
                        .font(.body.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
                Slider(
                    value: $model.clockMHz,
                    in: EmulationPreferences.minMHz...EmulationPreferences.maxMHz,
                    step: 0.05
                ) {
                    Text("Clock")
                } minimumValueLabel: {
                    Text("0.5")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } maximumValueLabel: {
                    Text("10")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                } onEditingChanged: { editing in
                    if !editing {
                        model.clockMHz = EmulationPreferences.snap(model.clockMHz)
                    }
                }
                .sensoryFeedback(.selection, trigger: detentFeedbackToken)
            } header: {
                Text("Emulation")
            } footer: {
                Text("Target CPU clock while running. Sticky stops at 1.00 and 1.80 MHz.")
            }

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Settings")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
        }
        .onAppear { token = "" }
    }

    /// Changes when the snapped value is a detent, for haptic feedback.
    private var detentFeedbackToken: Int {
        let mhz = model.clockMHz
        if abs(mhz - 1.0) < 0.001 { return 1 }
        if abs(mhz - 1.8) < 0.001 { return 2 }
        return 0
    }

    @ViewBuilder
    private var tokenField: some View {
        let field = SecureField("GitHub personal access token", text: $token)
            .autocorrectionDisabled()
        #if os(iOS)
        field
            .textInputAutocapitalization(.never)
        #else
        field
        #endif
    }
}
