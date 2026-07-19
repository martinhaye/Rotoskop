import SwiftUI
import RotoskopGit

/// Project file tree (DESIGN §2). Opens files into the Editor tab via `ProjectWorkspace`.
struct FileBrowserView: View {
    @ObservedObject var workspace: ProjectWorkspace

    @State private var createTargetDirectory = ""
    @State private var showCreateFile = false
    @State private var showCreateFolder = false
    @State private var newItemName = ""
    @State private var renamePath: String?
    @State private var renameText = ""
    @State private var movePath: String?
    @State private var moveText = ""
    @State private var deletePath: String?

    var body: some View {
        Group {
            if workspace.tree.isEmpty {
                ContentUnavailableView(
                    "Empty Project",
                    systemImage: "folder",
                    description: Text("Create a file to get started.")
                )
            } else {
                ScrollViewReader { proxy in
                    List {
                        ForEach(workspace.tree) { node in
                            FileNodeRow(
                                node: node,
                                onOpen: { workspace.openFile($0) },
                                onCreateFile: { beginCreateFile(in: $0) },
                                onCreateFolder: { beginCreateFolder(in: $0) },
                                onRename: { beginRename($0) },
                                onMove: { beginMove($0) },
                                onDelete: { deletePath = $0 },
                                onExpand: { path in
                                    DispatchQueue.main.async {
                                        withAnimation {
                                            proxy.scrollTo(path, anchor: .top)
                                        }
                                    }
                                }
                            )
                            .id(node.relativePath)
                        }
                    }
                    .listStyle(.plain)
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("New File") { beginCreateFile(in: "") }
                    Button("New Folder") { beginCreateFolder(in: "") }
                    Button("Refresh", systemImage: "arrow.clockwise") {
                        workspace.refreshTree()
                    }
                } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .alert("New File", isPresented: $showCreateFile) {
            TextField("name.s", text: $newItemName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                workspace.createFile(named: newItemName, inDirectory: createTargetDirectory)
            }
        } message: {
            Text(createTargetDirectory.isEmpty
                 ? "Creates in project root."
                 : "Creates in \(createTargetDirectory)/")
        }
        .alert("New Folder", isPresented: $showCreateFolder) {
            TextField("folder name", text: $newItemName)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) {}
            Button("Create") {
                workspace.createDirectory(named: newItemName, inDirectory: createTargetDirectory)
            }
        } message: {
            Text(createTargetDirectory.isEmpty
                 ? "Creates in project root."
                 : "Creates in \(createTargetDirectory)/")
        }
        .alert("Rename", isPresented: renamePresented) {
            TextField("New name", text: $renameText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { renamePath = nil }
            Button("Rename") {
                if let path = renamePath {
                    workspace.rename(relativePath: path, to: renameText)
                }
                renamePath = nil
            }
        }
        .alert("Move", isPresented: movePresented) {
            TextField("New relative path", text: $moveText)
                .autocorrectionDisabled()
            Button("Cancel", role: .cancel) { movePath = nil }
            Button("Move") {
                if let path = movePath {
                    workspace.move(from: path, to: moveText)
                }
                movePath = nil
            }
        } message: {
            Text("Enter the full project-relative destination path.")
        }
        .confirmationDialog(
            "Delete?",
            isPresented: deletePresented,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                if let path = deletePath {
                    workspace.delete(relativePath: path)
                }
                deletePath = nil
            }
            Button("Cancel", role: .cancel) { deletePath = nil }
        } message: {
            if let path = deletePath {
                Text("Delete \(path)? This cannot be undone.")
            }
        }
        .onAppear { workspace.refreshTree() }
    }

    private func beginCreateFile(in directory: String) {
        createTargetDirectory = directory
        newItemName = ""
        showCreateFile = true
    }

    private func beginCreateFolder(in directory: String) {
        createTargetDirectory = directory
        newItemName = ""
        showCreateFolder = true
    }

    private func beginRename(_ path: String) {
        renamePath = path
        renameText = (path as NSString).lastPathComponent
    }

    private func beginMove(_ path: String) {
        movePath = path
        moveText = path
    }

    private var renamePresented: Binding<Bool> {
        Binding(get: { renamePath != nil }, set: { if !$0 { renamePath = nil } })
    }

    private var movePresented: Binding<Bool> {
        Binding(get: { movePath != nil }, set: { if !$0 { movePath = nil } })
    }

    private var deletePresented: Binding<Bool> {
        Binding(get: { deletePath != nil }, set: { if !$0 { deletePath = nil } })
    }
}

private struct FileNodeRow: View {
    let node: ProjectFileSystem.Node
    let onOpen: (String) -> Void
    let onCreateFile: (String) -> Void
    let onCreateFolder: (String) -> Void
    let onRename: (String) -> Void
    let onMove: (String) -> Void
    let onDelete: (String) -> Void
    let onExpand: (String) -> Void

    @State private var isExpanded = false

    var body: some View {
        if node.isDirectory {
            DisclosureGroup(isExpanded: $isExpanded) {
                ForEach(node.children) { child in
                    FileNodeRow(
                        node: child,
                        onOpen: onOpen,
                        onCreateFile: onCreateFile,
                        onCreateFolder: onCreateFolder,
                        onRename: onRename,
                        onMove: onMove,
                        onDelete: onDelete,
                        onExpand: onExpand
                    )
                    .id(child.relativePath)
                }
            } label: {
                Label(node.name, systemImage: folderIcon)
                    .contextMenu { directoryMenu }
            }
            .onChange(of: isExpanded) { _, expanded in
                if expanded {
                    onExpand(node.relativePath)
                }
            }
        } else {
            Button {
                onOpen(node.relativePath)
            } label: {
                Label(node.name, systemImage: fileIcon)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .contextMenu { fileMenu }
        }
    }

    private var folderIcon: String {
        node.name == "build" ? "folder.fill" : "folder"
    }

    private var fileIcon: String {
        ProjectFileSystem.isAssemblyFile(node.relativePath)
            ? "chevron.left.forwardslash.chevron.right"
            : "doc"
    }

    @ViewBuilder
    private var directoryMenu: some View {
        Button("New File") { onCreateFile(node.relativePath) }
        Button("New Folder") { onCreateFolder(node.relativePath) }
        Button("Rename") { onRename(node.relativePath) }
        Button("Move…") { onMove(node.relativePath) }
        Divider()
        Button("Delete", role: .destructive) { onDelete(node.relativePath) }
    }

    @ViewBuilder
    private var fileMenu: some View {
        Button("Open") { onOpen(node.relativePath) }
        Button("Rename") { onRename(node.relativePath) }
        Button("Move…") { onMove(node.relativePath) }
        Divider()
        Button("Delete", role: .destructive) { onDelete(node.relativePath) }
    }
}
