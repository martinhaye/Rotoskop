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
