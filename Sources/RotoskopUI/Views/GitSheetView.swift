import RotoskopGit
import SwiftUI

/// Git sheet: status, commit, branch, merge-if-clean, push/pull (DESIGN §1.2 / §7.2).
struct GitSheetView: View {
    let project: ProjectRecord
    @ObservedObject var model: AppModel
    @Environment(\.dismiss) private var dismiss

    @State private var status: GitStatus?
    @State private var branches: [String] = []
    @State private var commitMessage = ""
    @State private var newBranchName = ""
    @State private var mergeRef = ""
    @State private var infoMessage: String?
    @State private var errorMessage: String?
    @State private var isBusy = false

    private let authorName = "Rotoskop"
    private let authorEmail = "rotoskop@local"

    var body: some View {
        List {
            statusSection
            commitSection
            branchSection
            syncSection
            mergeSection
            if let infoMessage {
                Section { Text(infoMessage).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle("Git")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") { dismiss() }
            }
        }
        .overlay { busyOverlay }
        .alert("Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) { errorMessage = nil }
        } message: {
            Text(errorMessage ?? "")
        }
        .task { await reload() }
    }

    @ViewBuilder
    private var statusSection: some View {
        Section("Status") {
            if let status {
                Text(status.branch.map { "Branch: \($0)" } ?? "Detached HEAD")
                    .font(.subheadline)
                if status.files.isEmpty {
                    Text("Working tree clean").foregroundStyle(.secondary)
                } else {
                    ForEach(status.files) { file in
                        HStack {
                            Text(file.kind.rawValue)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .frame(width: 72, alignment: .leading)
                            Text(file.path).lineLimit(1)
                        }
                    }
                }
            } else {
                Text("Loading…").foregroundStyle(.secondary)
            }
            Button("Refresh") { Task { await reload() } }
        }
    }

    @ViewBuilder
    private var commitSection: some View {
        Section("Commit") {
            TextField("Commit message", text: $commitMessage, axis: .vertical)
                .lineLimit(2...4)
            Button("Commit All Changes") {
                Task { await commitAll() }
            }
            .disabled(commitMessage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var branchSection: some View {
        Section("Branch") {
            ForEach(branches, id: \.self) { name in
                Button {
                    Task { await switchTo(name) }
                } label: {
                    branchLabel(name)
                }
            }
            HStack {
                TextField("New branch", text: $newBranchName)
                    .autocorrectionDisabled()
                Button("Create") {
                    Task { await createBranch() }
                }
                .disabled(newBranchName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
    }

    private func branchLabel(_ name: String) -> some View {
        HStack {
            Text(name)
            if name == status?.branch {
                Spacer()
                Image(systemName: "checkmark")
            }
        }
    }

    @ViewBuilder
    private var syncSection: some View {
        Section("Sync") {
            Button("Pull") { Task { await pull() } }
            Button("Push") { Task { await push() } }
        }
    }

    @ViewBuilder
    private var mergeSection: some View {
        Section("Merge (clean only)") {
            TextField("Branch or ref to merge", text: $mergeRef)
                .autocorrectionDisabled()
            Button("Merge If Clean") {
                Task { await merge() }
            }
            .disabled(mergeRef.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if isBusy {
            ProgressView()
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { if !$0 { errorMessage = nil } }
        )
    }

    private func repo() throws -> GitRepository {
        try model.store.openRepository(for: project)
    }

    private func reload() async {
        do {
            let repository = try repo()
            status = try repository.status()
            branches = try repository.listBranches()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func commitAll() async {
        await run {
            let repository = try repo()
            let result = try repository.commitAll(
                message: commitMessage,
                authorName: authorName,
                authorEmail: authorEmail
            )
            commitMessage = ""
            infoMessage = "Committed \(result.oid.prefix(7))"
            await reload()
        }
    }

    private func createBranch() async {
        await run {
            let name = newBranchName.trimmingCharacters(in: .whitespacesAndNewlines)
            try repo().createBranch(name, checkout: true)
            newBranchName = ""
            infoMessage = "Created and checked out \(name)"
            await reload()
        }
    }

    private func switchTo(_ name: String) async {
        await run {
            try repo().switchBranch(name)
            infoMessage = "Switched to \(name)"
            await reload()
        }
    }

    private func pull() async {
        await run {
            let result = try await repo().pull()
            infoMessage = describe(result)
            await reload()
        }
    }

    private func push() async {
        await run {
            try await repo().push()
            infoMessage = "Pushed"
            await reload()
        }
    }

    private func merge() async {
        await run {
            let ref = mergeRef.trimmingCharacters(in: .whitespacesAndNewlines)
            let result = try repo().mergeClean(from: ref)
            infoMessage = describe(result)
            await reload()
        }
    }

    private func describe(_ result: GitMergeResult) -> String {
        switch result {
        case .upToDate: return "Already up to date"
        case .fastForward(let oid): return "Fast-forwarded to \(oid.prefix(7))"
        case .merged(let oid): return "Merged \(oid.prefix(7))"
        }
    }

    private func run(_ work: () async throws -> Void) async {
        isBusy = true
        errorMessage = nil
        defer { isBusy = false }
        do {
            try await work()
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}
