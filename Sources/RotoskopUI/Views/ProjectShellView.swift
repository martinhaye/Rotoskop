import RotoskopGit
import SwiftUI

#if os(iOS)
import UIKit
#endif

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

    private var isRunTab: Bool { workspace.selectedTab == .run }
    private var isEditorTab: Bool { workspace.selectedTab == .editor }

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
        .navigationTitle(isRunTab ? "" : title)
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        // Editor/Run are tab switches, not pushes — hijack back so it stays in-project.
        .navigationBarBackButtonHidden(isEditorTab || isRunTab)
        #endif
        .toolbar {
            #if os(iOS)
            if isEditorTab {
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
            } else if isRunTab {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        workspace.selectedTab = workspace.tabBeforeRun
                    } label: {
                        HStack(spacing: 4) {
                            Image(systemName: "chevron.left")
                            Text(backLabel(for: workspace.tabBeforeRun))
                        }
                    }
                }
                if !workspace.runStatus.isEmpty {
                    ToolbarItem(placement: .principal) {
                        Text(workspace.runStatus)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
            #endif

            if isEditorTab {
                // Editor needs room for ⋯; Git lives on Files (and other tabs).
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

                    editorOverflowMenu
                }
            } else if isRunTab {
                ToolbarItemGroup(placement: .primaryAction) {
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
                }
            } else {
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
        .onChange(of: workspace.selectedTab) { previous, tab in
            if tab == .run, previous != .run {
                workspace.tabBeforeRun = previous
            }
            workspace.setRunTabActive(tab == .run)
        }
        .onAppear {
            workspace.setRunTabActive(workspace.selectedTab == .run)
        }
    }

    @ViewBuilder
    private var editorOverflowMenu: some View {
        Menu {
            #if os(iOS)
            Button("Select") {
                NotificationCenter.default.post(name: .rotoskopEditorSelect, object: nil)
            }
            Button("Select All") {
                NotificationCenter.default.post(name: .rotoskopEditorSelectAll, object: nil)
            }
            Divider()
            Button("Cut") {
                UIApplication.shared.sendAction(
                    #selector(UIResponderStandardEditActions.cut(_:)), to: nil, from: nil, for: nil
                )
            }
            Button("Copy") {
                UIApplication.shared.sendAction(
                    #selector(UIResponderStandardEditActions.copy(_:)), to: nil, from: nil, for: nil
                )
            }
            Button("Paste") {
                UIApplication.shared.sendAction(
                    #selector(UIResponderStandardEditActions.paste(_:)), to: nil, from: nil, for: nil
                )
            }
            Button("Undo") {
                UIApplication.shared.sendAction(Selector(("undo:")), to: nil, from: nil, for: nil)
            }
            Divider()
            #endif
            Button("Save Now") { _ = workspace.saveDocumentNow() }
                .disabled(!workspace.isDocumentDirty)
        } label: {
            Image(systemName: "ellipsis.circle")
        }
    }

    private var title: String {
        if let branchName {
            return "\(project.name) · \(branchName)"
        }
        return project.name
    }

    private func backLabel(for tab: ProjectWorkspace.Tab) -> String {
        switch tab {
        case .files: return "Files"
        case .editor: return "Editor"
        case .build: return "Build"
        case .run: return "Files"
        }
    }

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { workspace.errorMessage != nil },
            set: { if !$0 { workspace.errorMessage = nil } }
        )
    }
}
