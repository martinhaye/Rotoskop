import Foundation
import RotoskopCore
import RotoskopGit
import SwiftUI

#if os(iOS)
import UIKit
#elseif os(macOS)
import AppKit
#endif

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

    /// Last scroll offset Y per relative path (session memory; not persisted to disk).
    private var scrollOffsets: [String: CGFloat] = [:]

    @Published var buildLog: [String] = []
    @Published var buildDiagnostics: [Diagnostic] = []
    @Published var buildArtifacts: [String] = []
    @Published var isBuilding = false
    @Published var lastBuildSucceeded: Bool?

    @Published var screenText = ""
    @Published var screenDisplay = AttributedString()
    @Published var runStatus = "Idle"
    @Published var isRunning = false
    @Published var stopReasonText: String?
    @Published var registerDump: String?
    /// Last key byte injected (debug aid for interactive keyboard).
    @Published var lastInjectedKey: String?

    private var autosaveTask: Task<Void, Never>?
    private let autosaveDelayNanoseconds: UInt64 = 500_000_000
    private let fileManager: FileManager
    private let emuQueue = DispatchQueue(label: "rotoskop.emulator")
    private let sessionBox = EmulatorSessionBox()
    /// Bumped on each start/stop so an old run's completion cannot clobber a newer session.
    private var runGeneration = 0
    private var runTabActive = false

    /// Thread-safe holder so the run loop stays off the MainActor.
    private final class EmulatorSessionBox: @unchecked Sendable {
        private let lock = NSLock()
        private var keyboard: Keyboard?
        private var control: RunControl?
        private weak var cpu: CPU?
        private var generation = 0

        func install(keyboard: Keyboard, control: RunControl, cpu: CPU, generation: Int) {
            lock.lock()
            self.keyboard = keyboard
            self.control = control
            self.cpu = cpu
            self.generation = generation
            lock.unlock()
        }

        func clear(generation: Int? = nil) {
            lock.lock()
            if let generation, self.generation != generation {
                lock.unlock()
                return
            }
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

        func setPaused(_ paused: Bool, mhz: Double? = nil) {
            lock.lock()
            if let mhz {
                control?.targetMHz = mhz
            }
            control?.setPaused(paused)
            lock.unlock()
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
        private var paused = false
        var targetMHz: Double

        init(targetMHz: Double) {
            self.targetMHz = targetMHz
        }

        func stop() {
            lock.lock()
            stopped = true
            paused = false
            lock.unlock()
        }

        func setPaused(_ value: Bool) {
            lock.lock()
            paused = value
            lock.unlock()
        }

        var isStopped: Bool {
            lock.lock()
            defer { lock.unlock() }
            return stopped
        }

        var isPaused: Bool {
            lock.lock()
            defer { lock.unlock() }
            return paused
        }

        func currentMHz() -> Double {
            lock.lock()
            defer { lock.unlock() }
            return targetMHz
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

    /// Scroll Y to restore for the current file (0 if never opened this session).
    var savedScrollOffsetY: CGFloat {
        guard let path = openFilePath else { return 0 }
        return scrollOffsets[path] ?? 0
    }

    func updateScrollOffsetY(_ y: CGFloat) {
        guard let path = openFilePath else { return }
        scrollOffsets[path] = max(0, y)
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
            if let saved = scrollOffsets.removeValue(forKey: relativePath) {
                scrollOffsets[newRelativePath] = saved
            }
            let prefix = relativePath + "/"
            for key in scrollOffsets.keys.filter({ $0.hasPrefix(prefix) }) {
                if let saved = scrollOffsets.removeValue(forKey: key) {
                    scrollOffsets[newRelativePath + key.dropFirst(relativePath.count)] = saved
                }
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
            scrollOffsets.removeValue(forKey: relativePath)
            let prefix = relativePath + "/"
            for key in scrollOffsets.keys.filter({ $0 == relativePath || $0.hasPrefix(prefix) }) {
                scrollOffsets.removeValue(forKey: key)
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

    /// Pause the emulator when leaving the Run tab; resume (with current Settings MHz) when returning.
    func setRunTabActive(_ active: Bool) {
        runTabActive = active
        guard isRunning else { return }
        if active {
            let mhz = EmulationPreferences.clockMHz
            sessionBox.setPaused(false, mhz: mhz)
            runStatus = EmulationPreferences.formatMHz(mhz)
        } else {
            sessionBox.setPaused(true)
            runStatus = "Paused"
        }
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
        stopEmulator()
        selectedTab = .run
        setRunTabActive(true)

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
                setRunTabActive(false)
                runStatus = "Build failed — fix diagnostics before Run"
                return
            }
            selectedTab = .run
            setRunTabActive(true)
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
        runGeneration += 1
        sessionBox.stop()
        sessionBox.clear()
        isRunning = false
        lastInjectedKey = nil
        if runStatus == "Running…"
            || runStatus == "Building first…"
            || runStatus == "Paused"
            || runStatus.hasSuffix("MHz")
        {
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
            // Show latched $C000 view (hi-bit set = key ready), not the raw inject byte.
            lastInjectedKey = String(format: "$%02X", key | 0x80)
        }
    }

    private func beginEmulator(session: RunSession) {
        runGeneration += 1
        let generation = runGeneration
        let mhz = EmulationPreferences.clockMHz
        let control = RunControl(targetMHz: mhz)
        if !runTabActive {
            control.setPaused(true)
        }
        isRunning = true
        stopReasonText = nil
        registerDump = nil
        lastInjectedKey = nil
        screenText = ""
        screenDisplay = AttributedString()
        runStatus = runTabActive ? EmulationPreferences.formatMHz(mhz) : "Paused"

        let batchSeconds = 0.005
        let budgetNanos = UInt64(batchSeconds * 1_000_000_000.0)
        /// Refresh text screen ~60 Hz; rate text still updates every batch.
        let uiEveryBatches = 3

        emuQueue.async { [sessionBox] in
            do {
                let sim = Simulator(config: session.simulatorConfig)
                if let disk = session.disk {
                    try sim.setupHardDrive(imagePath: disk)
                }
                let kbd = sim.ensureInteractiveKeyboard()
                try sim.load()
                sessionBox.install(keyboard: kbd, control: control, cpu: sim.cpu, generation: generation)

                var finalReason: StopReason = .instructionLimit
                var nextDeadline = DispatchTime.now()
                var rateWindowStart = nextDeadline
                var cyclesAtRateWindowStart = sim.cycleCount
                var batchesSinceUI = uiEveryBatches // force first paint promptly
                var wasPaused = control.isPaused

                while !control.isStopped {
                    while control.isPaused && !control.isStopped {
                        wasPaused = true
                        Thread.sleep(forTimeInterval: 0.05)
                    }
                    if control.isStopped { break }

                    // After a pause, restart the wall-clock schedule so catch-up
                    // doesn't try to "owe" cycles for time spent paused.
                    if wasPaused {
                        wasPaused = false
                        nextDeadline = DispatchTime.now()
                        rateWindowStart = nextDeadline
                        cyclesAtRateWindowStart = sim.cycleCount
                    }

                    let targetMHz = control.currentMHz()
                    let cyclesTarget = max(1, Int((targetMHz * 1_000_000.0 * batchSeconds).rounded()))

                    let reason = sim.run(maxCycles: cyclesTarget, trace: false)

                    nextDeadline = DispatchTime(
                        uptimeNanoseconds: nextDeadline.uptimeNanoseconds &+ budgetNanos
                    )
                    let nowAfterRun = DispatchTime.now()
                    if nowAfterRun.uptimeNanoseconds < nextDeadline.uptimeNanoseconds {
                        Self.waitUntil(nextDeadline)
                    } else if nowAfterRun.uptimeNanoseconds
                        > nextDeadline.uptimeNanoseconds &+ budgetNanos &* 4
                    {
                        // Hopelessly behind (e.g. debugger) — snap schedule forward.
                        nextDeadline = nowAfterRun
                    }
                    // else: slightly behind → no sleep; next iterations catch up.

                    let now = DispatchTime.now()
                    let windowNanos = now.uptimeNanoseconds &- rateWindowStart.uptimeNanoseconds
                    let windowCycles = sim.cycleCount - cyclesAtRateWindowStart
                    let effectiveMHz: Double
                    if windowNanos > 5_000_000 {
                        effectiveMHz = Double(windowCycles)
                            / (Double(windowNanos) / 1_000_000_000.0)
                            / 1_000_000.0
                    } else {
                        effectiveMHz = targetMHz
                    }

                    batchesSinceUI += 1
                    let paintUI = batchesSinceUI >= uiEveryBatches || reason != .instructionLimit
                    let cells: [[TextScreen.Cell]]?
                    let screen: String?
                    if paintUI {
                        batchesSinceUI = 0
                        let c = sim.dumpScreenCells()
                        cells = c
                        screen = TextScreen.dumpCellsToString(c)
                    } else {
                        cells = nil
                        screen = nil
                    }

                    DispatchQueue.main.async { [weak self] in
                        guard let self, self.runGeneration == generation, !control.isStopped else { return }
                        if let cells, let screen {
                            self.screenText = screen
                            self.screenDisplay = Self.attributedScreen(cells)
                        }
                        if !control.isPaused {
                            self.runStatus = EmulationPreferences.formatMHz(effectiveMHz)
                        }
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
                let cells = sim.dumpScreenCells()
                let screen = TextScreen.dumpCellsToString(cells)
                sessionBox.clear(generation: generation)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.runGeneration == generation else { return }
                    self.screenText = screen
                    self.screenDisplay = Self.attributedScreen(cells)
                    self.registerDump = dump
                    self.stopReasonText = Self.describe(finalReason)
                    self.runStatus = Self.describe(finalReason)
                    self.isRunning = false
                    self.lastInjectedKey = nil
                }
            } catch {
                sessionBox.clear(generation: generation)
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.runGeneration == generation else { return }
                    self.errorMessage = error.localizedDescription
                    self.runStatus = "Error"
                    self.isRunning = false
                }
            }
        }
    }

    /// Sleep most of the way to `deadline`, then spin for the last ~0.1 ms so
    /// `Thread.sleep` overshoot does not stretch every batch.
    nonisolated private static func waitUntil(_ deadline: DispatchTime) {
        while true {
            let now = DispatchTime.now().uptimeNanoseconds
            let target = deadline.uptimeNanoseconds
            if now >= target { return }
            let remaining = target &- now
            if remaining > 150_000 {
                Thread.sleep(forTimeInterval: Double(remaining &- 80_000) / 1_000_000_000.0)
            }
            // else: busy-wait the last ~0.15 ms
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

    /// Render Apple II inverse/flash (hi-bit clear) as reverse video.
    private static func attributedScreen(_ lines: [[TextScreen.Cell]]) -> AttributedString {
        var result = AttributedString()
        for (i, line) in lines.enumerated() {
            if i > 0 { result.append(AttributedString("\n")) }
            for cell in line {
                var piece = AttributedString(String(cell.character))
                if cell.inverse {
                    piece.backgroundColor = .primary
                    piece.foregroundColor = Color(nsColorOrSystemBackground)
                }
                result.append(piece)
            }
        }
        return result
    }

    private static var nsColorOrSystemBackground: Color {
        #if os(iOS)
        Color(uiColor: .systemBackground)
        #else
        Color(nsColor: .textBackgroundColor)
        #endif
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
