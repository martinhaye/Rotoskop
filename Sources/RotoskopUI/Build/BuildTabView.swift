import RotoskopCore
import SwiftUI

/// Build tab: run YAML pipeline, show log, jump diagnostics to Editor (DESIGN §7.2).
struct BuildTabView: View {
    @ObservedObject var workspace: ProjectWorkspace

    private var isBusy: Bool { workspace.isBuilding || workspace.isTesting }

    var body: some View {
        List {
            Section {
                Button {
                    Task { _ = await workspace.runBuild() }
                } label: {
                    if workspace.isBuilding {
                        Label("Building…", systemImage: "hammer.fill")
                    } else {
                        Label("Build", systemImage: "hammer")
                    }
                }
                .disabled(isBusy)

                Button {
                    Task { await workspace.runTests() }
                } label: {
                    if workspace.isTesting {
                        Label("Testing…", systemImage: "checkmark.diamond.fill")
                    } else {
                        Label("Run tests", systemImage: "checkmark.diamond")
                    }
                }
                .disabled(isBusy || workspace.lastBuildSucceeded != true)

                if let ok = workspace.lastTestSucceeded {
                    Text(ok ? "Last test run succeeded" : "Last test run failed")
                        .font(.subheadline)
                        .foregroundStyle(ok ? Color.secondary : Color.red)
                } else if let ok = workspace.lastBuildSucceeded {
                    Text(ok ? "Last build succeeded" : "Last build failed")
                        .font(.subheadline)
                        .foregroundStyle(ok ? Color.secondary : Color.red)
                }
            }

            if !workspace.buildDiagnostics.isEmpty {
                Section("Diagnostics") {
                    ForEach(Array(workspace.buildDiagnostics.enumerated()), id: \.offset) { _, diag in
                        Button {
                            workspace.openDiagnostic(diag)
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(workspace.displayDescription(for: diag))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(diag.severity == .error ? .red : .primary)
                                    .multilineTextAlignment(.leading)
                                if diag.location != nil {
                                    Text("Tap to open in Editor")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .disabled(diag.location == nil && workspace.openFilePath == nil)
                    }
                }
            }

            if !workspace.buildLog.isEmpty {
                Section(workspace.lastTestSucceeded != nil ? "Test log" : "Log") {
                    ForEach(Array(workspace.buildLog.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .font(.caption.monospaced())
                            .textSelection(.enabled)
                    }
                }
            }

            if !workspace.buildArtifacts.isEmpty, workspace.lastTestSucceeded == nil {
                Section("Artifacts") {
                    ForEach(workspace.buildArtifacts, id: \.self) { path in
                        Button {
                            if path.hasSuffix(".lst") || path.hasSuffix(".s") || path.hasSuffix(".i")
                                || path.hasSuffix(".yaml") || path.hasSuffix(".md") || path.hasSuffix(".js")
                                || path.hasSuffix(".txt") {
                                workspace.openFile(path)
                            }
                        } label: {
                            Text(path)
                                .font(.caption.monospaced())
                                .foregroundStyle(.primary)
                        }
                        .disabled(!(path.hasSuffix(".lst") || path.hasSuffix(".s") || path.hasSuffix(".i")
                                    || path.hasSuffix(".yaml") || path.hasSuffix(".md") || path.hasSuffix(".js")
                                    || path.hasSuffix(".txt")))
                    }
                }
            }
        }
        .overlay {
            if isBusy {
                ProgressView()
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
            }
        }
    }
}
