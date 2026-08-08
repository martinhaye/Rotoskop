import RotoskopGit
import SwiftUI

/// Colorized unified diff for one changed file, with an optional restore-to-HEAD action.
struct GitFileDiffView: View {
    let project: ProjectRecord
    let file: GitFileStatus
    @ObservedObject var model: AppModel
    @ObservedObject var workspace: ProjectWorkspace
    let onReverted: () -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var diff: GitFileDiff?
    @State private var errorMessage: String?
    @State private var isBusy = false
    @State private var showRevertConfirmation = false

    var body: some View {
        Group {
            if let diff {
                if diff.lines.isEmpty {
                    ContentUnavailableView(
                        "No Textual Changes",
                        systemImage: "doc.text.magnifyingglass",
                        description: Text("The file may contain binary or metadata-only changes.")
                    )
                } else {
                    diffContent(diff)
                }
            } else {
                ProgressView("Loading diff…")
            }
        }
        .navigationTitle((file.path as NSString).lastPathComponent)
        .toolbar {
            if file.kind != .untracked {
                ToolbarItem(placement: .primaryAction) {
                    Button("Revert", role: .destructive) {
                        showRevertConfirmation = true
                    }
                    .disabled(isBusy)
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
        .confirmationDialog(
            "Discard changes?",
            isPresented: $showRevertConfirmation,
            titleVisibility: .visible
        ) {
            Button("Discard Changes", role: .destructive) {
                Task { await discardChanges() }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Restore \(file.path) to the version in the last commit? This cannot be undone.")
        }
        .alert("Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await loadDiff() }
    }

    private func diffContent(_ diff: GitFileDiff) -> some View {
        ScrollView([.horizontal, .vertical]) {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(diff.lines) { line in
                    Text(line.text.isEmpty ? " " : line.text)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(foregroundColor(for: line.kind))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 1)
                        .background(backgroundColor(for: line.kind))
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .padding(.vertical, 8)
        }
    }

    private func foregroundColor(for kind: GitFileDiff.Line.Kind) -> Color {
        switch kind {
        case .addition: return .green
        case .deletion: return .red
        case .hunk: return .blue
        case .metadata: return .secondary
        case .context: return .primary
        }
    }

    private func backgroundColor(for kind: GitFileDiff.Line.Kind) -> Color {
        switch kind {
        case .addition: return Color.green.opacity(0.12)
        case .deletion: return Color.red.opacity(0.12)
        case .hunk: return Color.blue.opacity(0.08)
        case .metadata, .context: return .clear
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func repository() throws -> GitRepository {
        try model.store.openRepository(for: project)
    }

    private func loadDiff() async {
        do {
            diff = try repository().diff(at: file.path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func discardChanges() async {
        isBusy = true
        defer { isBusy = false }
        do {
            let affectedPaths = try repository().discardChanges(at: file.path)
            workspace.refreshAfterGitChange(affectedPaths: affectedPaths)
            onReverted()
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
