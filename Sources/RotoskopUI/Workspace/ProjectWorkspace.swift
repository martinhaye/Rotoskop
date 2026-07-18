import Foundation
import RotoskopGit
import SwiftUI

/// Shared Files/Editor state for one open project (DESIGN §2–3 / §7.2).
@MainActor
final class ProjectWorkspace: ObservableObject {
    enum Tab: Hashable {
        case files
        case editor
        case build
        case run
    }

    let rootURL: URL
    let projectName: String

    @Published var selectedTab: Tab = .files
    @Published var tree: [ProjectFileSystem.Node] = []
    @Published var openFilePath: String?
    @Published var documentText: String = ""
    @Published var isDocumentDirty = false
    @Published var errorMessage: String?
    @Published var statusMessage: String?

    /// In-editor diagnostic banner (wired fully in step 7; storage ready now).
    @Published var diagnosticBanner: String?

    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelayNanoseconds: UInt64 = 500_000_000 // 0.5s
    private let fileManager: FileManager

    var openFileName: String? {
        openFilePath.map { ($0 as NSString).lastPathComponent }
    }

    var openFileKind: EditorInputRules.FileKind {
        guard let openFilePath else { return .plain }
        return EditorInputRules.FileKind.kind(forRelativePath: openFilePath)
    }

    init(rootURL: URL, projectName: String, fileManager: FileManager = .default) {
        self.rootURL = rootURL
        self.projectName = projectName
        self.fileManager = fileManager
    }

    func refreshTree() {
        do {
            tree = try ProjectFileSystem.listTree(rootURL: rootURL, fileManager: fileManager)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openFile(_ relativePath: String) {
        autosaveTask?.cancel()
        if isDocumentDirty {
            saveDocumentNow()
        }
        do {
            let text = try ProjectFileSystem.readText(
                rootURL: rootURL,
                relativePath: relativePath,
                fileManager: fileManager
            )
            openFilePath = relativePath
            documentText = text
            isDocumentDirty = false
            diagnosticBanner = nil
            statusMessage = nil
            selectedTab = .editor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func applyEditorText(_ newText: String) {
        guard openFilePath != nil else { return }
        documentText = newText
        isDocumentDirty = true
        scheduleAutosave()
    }

    func scheduleAutosave() {
        autosaveTask?.cancel()
        autosaveTask = Task { [weak self] in
            guard let self else { return }
            try? await Task.sleep(nanoseconds: autosaveDelayNanoseconds)
            guard !Task.isCancelled else { return }
            await MainActor.run { _ = self.saveDocumentNow() }
        }
    }

    @discardableResult
    func saveDocumentNow() -> Bool {
        autosaveTask?.cancel()
        guard let path = openFilePath, isDocumentDirty else { return true }
        do {
            try ProjectFileSystem.writeText(
                documentText,
                rootURL: rootURL,
                relativePath: path,
                fileManager: fileManager
            )
            isDocumentDirty = false
            statusMessage = "Saved"
            errorMessage = nil
            return true
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
    }

    func createFile(named name: String, inDirectory directory: String) {
        do {
            let path = try ProjectFileSystem.createFile(
                named: name,
                inDirectory: directory,
                rootURL: rootURL,
                fileManager: fileManager
            )
            refreshTree()
            openFile(path)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func createDirectory(named name: String, inDirectory directory: String) {
        do {
            _ = try ProjectFileSystem.createDirectory(
                named: name,
                inDirectory: directory,
                rootURL: rootURL,
                fileManager: fileManager
            )
            refreshTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func rename(relativePath: String, to newName: String) {
        let parent = (relativePath as NSString).deletingLastPathComponent
        let dest = parent.isEmpty || parent == "." ? newName : "\(parent)/\(newName)"
        move(from: relativePath, to: dest)
    }

    func move(from relativePath: String, to newRelativePath: String) {
        if isDocumentDirty, openFilePath == relativePath {
            saveDocumentNow()
        }
        do {
            try ProjectFileSystem.move(
                from: relativePath,
                to: newRelativePath,
                rootURL: rootURL,
                fileManager: fileManager
            )
            if openFilePath == relativePath {
                openFilePath = newRelativePath
            } else if let open = openFilePath, open.hasPrefix(relativePath + "/") {
                openFilePath = newRelativePath + open.dropFirst(relativePath.count)
            }
            refreshTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func delete(relativePath: String) {
        do {
            try ProjectFileSystem.delete(
                relativePath: relativePath,
                rootURL: rootURL,
                fileManager: fileManager
            )
            if let open = openFilePath, open == relativePath || open.hasPrefix(relativePath + "/") {
                openFilePath = nil
                documentText = ""
                isDocumentDirty = false
            }
            refreshTree()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func flushBeforeLeaving() {
        autosaveTask?.cancel()
        _ = saveDocumentNow()
    }
}
