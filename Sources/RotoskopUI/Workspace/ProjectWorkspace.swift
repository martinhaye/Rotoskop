import Foundation
import RotoskopCore
import RotoskopGit
import SwiftUI

/// Shared project session: Files/Editor/Build/Run (DESIGN §2–3 / §7.2).
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

    @Published var diagnosticBanner: String?
    @Published var revealLine: Int?
    @Published var revealColumn: Int?

    @Published var buildLog: [String] = []
    @Published var buildDiagnostics: [Diagnostic] = []
    @Published var buildArtifacts: [String] = []
    @Published var isBuilding = false
    @Published var lastBuildSucceeded: Bool?

    @Published var screenText = ""
    @Published var runStatus = "Idle"
    @Published var isRunning = false
    @Published var stopReasonText: String?
    @Published var registerDump: String?

    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelayNanoseconds: UInt64 = 500_000_000
    private let fileManager: FileManager
    private let emuQueue = DispatchQueue(label: "rotoskop.emulator")
    private let sessionBox = EmulatorSessionBox()

    /// Thread-safe holder so the run loop stays off the MainActor.
    private final class EmulatorSessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var keyboard: Keyboard?
        private var control: RunControl?
        private weak var cpu: CPU?

        func install(keyboard: Keyboard, control: RunControl, cpu: CPU) {
            lock.lock()
            self.keyboard = keyboard
            self.control = control
            self.cpu = cpu
            lock.unlock()
        }

        func clear() {
            lock.lock()
            keyboard = nil
            control = nil
            cpu = nil
            lock.unlock()
        }

        func stop() {
            lock.lock()
            control?.stop()
            let cpu = self.cpu
            lock.unlock()
            cpu?.requestStop()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return control?.isStopped ?? true
        }

        func injectKey(_ key: UInt8) {
            lock.lock()
            let keyboard = self.keyboard
            lock.unlock()
            keyboard?.injectKey(key)
        }
    }

    private final class RunControl: @unchecked Sendable {
        private let lock = NSLock()
        private var stopped = false

        func stop() {
            lock.lock()
            stopped = true
            lock.unlock()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }
    }

    var openFileName: String? {
        openFilePath.map { ($0 as NSString).lastPathComponent }
    }

    var openFileKind: EditorInputRules.FileKind {
        guard let openFilePath else { return .plain }
        return EditorInputRules.FileKind.kind(forRelativePath: openFilePath)
    }

    var projectRootPath: String { rootURL.path }

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
            revealLine = nil
            revealColumn = nil
            statusMessage = nil
            selectedTab = .editor
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func openDiagnostic(_ diagnostic: Diagnostic) {
        guard let location = diagnostic.location else {
            diagnosticBanner = diagnostic.description
            selectedTab = .editor
            return
        }
        let relative = relativize(location.file)
        openFile(relative)
        diagnosticBanner = diagnostic.description
        revealLine = location.line
        revealColumn = max(1, location.column)
        selectedTab = .editor
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
        stopEmulator()
    }

    // MARK: - Build

    @discardableResult
    func runBuild(switchToBuildTab: Bool = true) async -> Bool {
        _ = saveDocumentNow()
        if switchToBuildTab {
            selectedTab = .build
        }
        isBuilding = true
        buildLog = ["Building…"]
        buildDiagnostics = []
        buildArtifacts = []
        lastBuildSucceeded = nil
        defer { isBuilding = false }

        let root = projectRootPath
        let result: BuildResult = await Task.detached(priority: .userInitiated) {
            do {
                let engine = try BuildEngine(projectRoot: root)
                return engine.build()
            } catch {
                return BuildResult(
                    diagnostics: [Diagnostic(.error, "\(error)")],
                    log: ["FAILED: \(error)"]
                )
            }
        }.value

        buildLog = result.log
        buildDiagnostics = result.diagnostics
        buildArtifacts = result.artifacts.map { relativize($0) }
        lastBuildSucceeded = result.succeeded
        refreshTree()

        if !result.succeeded, let first = result.diagnostics.first(where: { $0.location != nil }) {
            // Stay on Build (DESIGN §7.2); user can tap to jump.
            _ = first
        }
        return result.succeeded
    }

    // MARK: - Run

    func startRun() async {
        _ = saveDocumentNow()
        selectedTab = .run
        stopEmulator()

        let root = projectRootPath
        let needsBuild: Bool = await Task.detached(priority: .utility) {
            do {
                let config = try ProjectConfig.load(fromProjectRoot: root)
                return BuildDirtiness.isDirty(projectRoot: root, config: config)
            } catch {
                return true
            }
        }.value

        if needsBuild {
            runStatus = "Building first…"
            let ok = await runBuild(switchToBuildTab: false)
            if !ok {
                selectedTab = .build
                runStatus = "Build failed — fix diagnostics before Run"
                return
            }
            selectedTab = .run
        }

        do {
            let config = try ProjectConfig.load(fromProjectRoot: root)
            // Interactive: no scripted keys, no instruction cap from yaml.
            let session = try RunSession.from(
                projectRoot: root,
                config: config,
                profile: nil,
                cliKeys: [],
                cliMaxInstructions: Int.max / 4,
                cliTrace: false,
                cliScreen: false
            )
            beginEmulator(session: session)
        } catch {
            errorMessage = error.localizedDescription
            runStatus = "Failed to start"
        }
    }

    func stopEmulator() {
        sessionBox.stop()
        sessionBox.clear()
        isRunning = false
        if runStatus == "Running…" || runStatus == "Building first…" {
            runStatus = "Stopped"
        }
    }

    func injectCharacter(_ string: String) {
        guard isRunning else { return }
        for scalar in string.unicodeScalars {
            var key = UInt8(truncatingIfNeeded: scalar.value)
            if key == 0x0A { key = 0x0D }
            if key == 0x7F { key = 0x08 }
            sessionBox.injectKey(key)
        }
    }

    private func beginEmulator(session: RunSession) {
        let control = RunControl()
        isRunning = true
        stopReasonText = nil
        registerDump = nil
        screenText = ""
        runStatus = "Running…"

        emuQueue.async { [sessionBox] in
            do {
                let sim = Simulator(config: session.simulatorConfig)
                if let disk = session.disk {
                    try sim.setupHardDrive(imagePath: disk)
                }
                let kbd = sim.ensureInteractiveKeyboard()
                try sim.load()
                sessionBox.install(keyboard: kbd, control: control, cpu: sim.cpu)

                let chunk = 25_000
                var finalReason: StopReason = .instructionLimit
                while !control.isStopped {
                    let reason = sim.run(maxInstructions: chunk, trace: false)
                    let screen = sim.dumpScreen()
                    DispatchQueue.main.async { [weak self] in
                        guard let self, !control.isStopped else { return }
                        self.screenText = screen
                    }
                    if reason != .instructionLimit {
                        finalReason = reason
                        break
                    }
                }
                if control.isStopped {
                    finalReason = .explicitStop
                }

                let dump = sim.cpu.registerDump()
                let screen = sim.dumpScreen()
                sessionBox.clear()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.screenText = screen
                    self.registerDump = dump
                    self.stopReasonText = Self.describe(finalReason)
                    self.runStatus = Self.describe(finalReason)
                    self.isRunning = false
                }
            } catch {
                sessionBox.clear()
                DispatchQueue.main.async { [weak self] in
                    guard let self else { return }
                    self.errorMessage = error.localizedDescription
                    self.runStatus = "Error"
                    self.isRunning = false
                }
            }
        }
    }

    private static func describe(_ reason: StopReason) -> String {
        switch reason {
        case .success: return "Halted (success)"
        case .instructionLimit: return "Instruction limit"
        case .unhandledBRK: return "Unhandled BRK"
        case .illegalOpcode(let op): return String(format: "Illegal opcode $%02X", op)
        case .explicitStop: return "Stopped"
        case .ioError(let msg): return "I/O error: \(msg)"
        }
    }

    private func relativize(_ path: String) -> String {
        let root = rootURL.standardizedFileURL.path
        let standardized = (path as NSString).standardizingPath
        if standardized == root { return "" }
        let prefix = root.hasSuffix("/") ? root : root + "/"
        if standardized.hasPrefix(prefix) {
            return String(standardized.dropFirst(prefix.count))
        }
        return standardized
    }
}
