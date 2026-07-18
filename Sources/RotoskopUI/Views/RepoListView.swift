import RotoskopGit
import SwiftUI

struct RepoListView: View {
    @ObservedObject var model: AppModel
    @State private var showClone = false
    @State private var showSettings = false
    @State private var cloneURL = ""
    @State private var projectPendingDelete: ProjectRecord?

    var body: some View {
        listContent
            .navigationTitle("Projects")
            .navigationDestination(for: ProjectRecord.self) { project in
                ProjectShellView(project: project, model: model)
            }
            .toolbar { toolbarContent }
            .sheet(isPresented: $showSettings) {
                NavigationStack { SettingsView(model: model) }
            }
            .alert("Clone Repository", isPresented: $showClone) {
                TextField("https://github.com/owner/repo", text: $cloneURL)
                Button("Cancel", role: .cancel) {}
                Button("Clone") {
                    Task { await model.clone(remoteURL: cloneURL) }
                }
            } message: {
                Text("Clones into app-managed storage. Requires a GitHub PAT in Settings.")
            }
            .confirmationDialog(
                "Delete local clone?",
                isPresented: deleteDialogPresented,
                titleVisibility: .visible
            ) {
                Button("Delete", role: .destructive) {
                    if let project = projectPendingDelete {
                        model.remove(project)
                    }
                    projectPendingDelete = nil
                }
                Button("Cancel", role: .cancel) {
                    projectPendingDelete = nil
                }
            } message: {
                if let project = projectPendingDelete {
                    Text("Removes \(project.name) from the list and deletes the local clone.")
                }
            }
            .overlay { busyOverlay }
            .alert("Error", isPresented: errorPresented) {
                Button("OK", role: .cancel) { model.errorMessage = nil }
            } message: {
                Text(model.errorMessage ?? "")
            }
    }

    @ViewBuilder
    private var listContent: some View {
        List {
            if model.projects.isEmpty {
                ContentUnavailableView(
                    "No Projects",
                    systemImage: "externaldrive.badge.plus",
                    description: Text("Clone a GitHub repo to get started.")
                )
            } else {
                ForEach(model.projects) { project in
                    projectRow(project)
                }
            }
        }
    }

    private func projectRow(_ project: ProjectRecord) -> some View {
        NavigationLink(value: project) {
            VStack(alignment: .leading, spacing: 2) {
                Text(project.name).font(.headline)
                Text(project.remoteURL)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
            Button(role: .destructive) {
                projectPendingDelete = project
            } label: {
                Label("Delete", systemImage: "trash")
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button {
                showSettings = true
            } label: {
                Image(systemName: "gearshape")
            }
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                cloneURL = ""
                showClone = true
            } label: {
                Image(systemName: "plus")
            }
        }
    }

    @ViewBuilder
    private var busyOverlay: some View {
        if model.isBusy {
            ProgressView("Working…")
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var deleteDialogPresented: Binding<Bool> {
        Binding(
            get: { projectPendingDelete != nil },
            set: { if !$0 { projectPendingDelete = nil } }
        )
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )
    }
}
