import RotoskopGit
import SwiftUI

/// Project shell with portrait tabs (DESIGN §7.2).
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

            BuildTabView(workspace: workspace)
                .tabItem { Label("Build", systemImage: "hammer") }
                .tag(ProjectWorkspace.Tab.build)

            RunTabView(workspace: workspace)
                .tabItem { Label("Run", systemImage: "play.fill") }
                .tag(ProjectWorkspace.Tab.run)
        }
        .navigationTitle(title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Editor is a tab switch, not a push — hijack back so it returns to Files, not repos.
        .navigationBarBackButtonHidden(workspace.selectedTab == .editor)
        #endif
        .toolbar {
            #if os(iOS)
            if workspace.selectedTab == .editor {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        workspace.selectedTab = .files
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text("Files")
                        }
                    }
                }
            }
            #endif
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    Task { _ = await workspace.runBuild() }
                } label: {
                    Image(systemName: "hammer")
                }
                .disabled(workspace.isBuilding)

                Button {
                    Task { await workspace.startRun() }
                } label: {
                    Image(systemName: "play.fill")
                }
                .disabled(workspace.isBuilding)

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
