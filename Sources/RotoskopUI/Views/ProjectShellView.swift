import RotoskopGit
import SwiftUI

/// Project shell with portrait tabs (DESIGN §7.2). Files/Editor/Build/Run are stubs until steps 6–7.
struct ProjectShellView: View {
    let project: ProjectRecord
    @ObservedObject var model: AppModel
    @State private var showGit = false
    @State private var branchName: String?

    var body: some View {
        TabView {
            PlaceholderTab(
                title: "Files",
                systemImage: "folder",
                message: "File browser arrives in step 6."
            )
            .tabItem { Label("Files", systemImage: "folder") }

            PlaceholderTab(
                title: "Editor",
                systemImage: "chevron.left.forwardslash.chevron.right",
                message: "Editor arrives in step 6."
            )
            .tabItem { Label("Editor", systemImage: "chevron.left.forwardslash.chevron.right") }

            PlaceholderTab(
                title: "Build",
                systemImage: "hammer",
                message: "Build UI arrives in step 7."
            )
            .tabItem { Label("Build", systemImage: "hammer") }

            PlaceholderTab(
                title: "Run",
                systemImage: "play.fill",
                message: "Emulator UI arrives in step 7."
            )
            .tabItem { Label("Run", systemImage: "play.fill") }
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
        .task {
            branchName = try? model.store.openRepository(for: project).currentBranchName()
        }
    }

    private var title: String {
        if let branchName {
            return "\(project.name) · \(branchName)"
        }
        return project.name
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
