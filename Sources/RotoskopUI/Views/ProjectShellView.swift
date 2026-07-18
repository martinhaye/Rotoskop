import RotoskopGit
import SwiftUI

/// Project shell with portrait tabs (DESIGN §7.2). Build/Run remain stubs until step 7.
struct ProjectShellView: View {
    let project: ProjectRecord
    @ObservedObject var model: AppModel
    @StateObject private var workspace: ProjectWorkspace
    @State private var showGit = false
    @State private var branchName: String?

    init(project: ProjectRecord, model: AppModel) {
        self.project = project
        self.model = model
        let root = model.store.localURL(for: project)
        _workspace = StateObject(
            wrappedValue: ProjectWorkspace(rootURL: root, projectName: project.name)
        )
    }

    var body: some View {
        TabView(selection: $workspace.selectedTab) {
            FileBrowserView(workspace: workspace)
                .tabItem { Label("Files", systemImage: "folder") }
                .tag(ProjectWorkspace.Tab.files)

            EditorTabView(workspace: workspace)
                .tabItem { Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right") }
                .tag(ProjectWorkspace.Tab.editor)

            PlaceholderTab(
                title: "Build",
                systemImage: "hammer",
                message: "Build UI arrives in step 7."
            )
            .tabItem { Label("Build", systemImage: "hammer") }
            .tag(ProjectWorkspace.Tab.build)

            PlaceholderTab(
                title: "Run",
                systemImage: "play.fill",
                message: "Emulator UI arrives in step 7."
            )
            .tabItem { Label("Run", systemImage: "play.fill") }
            .tag(ProjectWorkspace.Tab.run)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button("Git") { showGit = true }
            }
        }
        .sheet(isPresented: $showGit) {
            NavigationStack {
                GitSheetView(project: project, model: model)
            }
        }
        .alert("Error", isPresented: errorPresented) {
            Button("OK", role: .cancel) { workspace.errorMessage = nil }
        } message: {
            Text(workspace.errorMessage ?? "")
        }
        .task {
            workspace.refreshTree()
            branchName = try? model.store.openRepository(for: project).currentBranchName()
        }
        .onDisappear {
            workspace.flushBeforeLeaving()
        }
    }

    private var title: String {
        if let branchName {
            return "\(project.name) · \(branchName)"
        }
        return project.name
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )
    }
}

private struct PlaceholderTab: View {
    let title: String
    let systemImage: String
    let message: String

    var body: some View {
        ContentUnavailableView(title, systemImage: systemImage, description: Text(message))
    }
}
