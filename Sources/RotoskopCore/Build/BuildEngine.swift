import Foundation
#if canImport(JavaScriptCore)
import JavaScriptCore
#endif

public struct BuildResult: Sendable {
    public var diagnostics: [Diagnostic]
    public var artifacts: [String]

    public var succeeded: Bool { !diagnostics.contains { $0.severity == .error } }
}

public final class BuildEngine {
    public let projectRoot: String
    public let config: ProjectConfig

    public init(projectRoot: String, config: ProjectConfig) {
        self.projectRoot = projectRoot
        self.config = config
    }

    public convenience init(projectRoot: String = ".") throws {
        let root = (projectRoot as NSString).standardizingPath
        let config = try ProjectConfig.load(fromProjectRoot: root)
        self.init(projectRoot: root, config: config)
    }

    @discardableResult
    public func build() -> BuildResult {
        var diagnostics: [Diagnostic] = []
        var artifacts: [String] = []
        let buildDir = abs(config.buildDir)
        mkdirp(buildDir)
        mkdirp(abs("\(config.buildDir)/generated"))

        for step in config.steps {
            do {
                switch step {
                case .generate(let language, let script, let out):
                    try runGenerate(language: language, script: script, out: out)
                    artifacts.append(abs(out))
                case .assemble(let sources, let out, let outDir):
                    let produced = try runAssemble(sources: sources, out: out, outDir: outDir)
                    artifacts.append(contentsOf: produced)
                case .packImage(let format, let out, let boot, let root, let dirs):
                    guard format == "runix_2mg" else {
                        throw BuildError.stepFailed("unsupported pack format \(format)")
                    }
                    let path = try runPack(out: out, boot: boot, root: root, dirs: dirs)
                    artifacts.append(path)
                }
            } catch {
                diagnostics.append(Diagnostic(.error, "\(error)"))
                return BuildResult(diagnostics: diagnostics, artifacts: artifacts)
            }
        }
        return BuildResult(diagnostics: diagnostics, artifacts: artifacts)
    }

    // MARK: - Steps

    private func runGenerate(language: String, script: String, out: String) throws {
        guard language == "js" else {
            throw BuildError.stepFailed("generate language '\(language)' not supported (v1: js)")
        }
        let scriptPath = abs(script)
        let source = try String(contentsOfFile: scriptPath, encoding: .utf8)
        let output = try JSGenerate.run(source: source, projectRoot: projectRoot)
        let outPath = abs(out)
        mkdirp((outPath as NSString).deletingLastPathComponent)
        try output.write(toFile: outPath, atomically: true, encoding: .utf8)
    }

    private func runAssemble(sources: [String], out: String?, outDir: String?) throws -> [String] {
        var includePaths = config.includeDirs.map { abs($0) }
        let generated = abs("\(config.buildDir)/generated")
        if FileManager.default.fileExists(atPath: generated) {
            includePaths.append(generated)
        }
        // Also allow includes next to sources (e.g. base_font.s in runes/)
        var produced: [String] = []
        let files = try expandSources(sources)
        for file in files {
            let srcDir = (file as NSString).deletingLastPathComponent
            var paths = includePaths
            if !paths.contains(srcDir) { paths.append(srcDir) }

            let asm = Assembler(options: AssembleOptions(includePaths: paths, generateListing: true))
            let result = asm.assemble(file: file)
            if !result.succeeded {
                let msgs = result.diagnostics.map(\.description).joined(separator: "\n")
                throw BuildError.stepFailed("assemble \(file) failed:\n\(msgs)")
            }

            let outPath: String
            if let out, files.count == 1 {
                outPath = abs("\(config.buildDir)/\(out)")
            } else if let outDir {
                let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                outPath = abs("\(config.buildDir)/\(outDir)/\(base).bin")
            } else {
                let base = ((file as NSString).lastPathComponent as NSString).deletingPathExtension
                outPath = abs("\(config.buildDir)/\(base).bin")
            }
            mkdirp((outPath as NSString).deletingLastPathComponent)
            try Data(result.binary).write(to: URL(fileURLWithPath: outPath))
            let lst = (outPath as NSString).deletingPathExtension + ".lst"
            try result.listing.write(toFile: lst, atomically: true, encoding: .utf8)
            produced.append(outPath)
        }
        return produced
    }

    private func runPack(out: String, boot: String, root: [(String, String)], dirs: [(String, [String])]) throws -> String {
        let bootData = try Data(contentsOf: URL(fileURLWithPath: abs("\(config.buildDir)/\(boot)")))
        var rootFiles: [(String, Data)] = []
        for (name, path) in root {
            let data = try Data(contentsOf: URL(fileURLWithPath: abs("\(config.buildDir)/\(path)")))
            rootFiles.append((name, data))
        }
        var directories: [(String, [(String, Data)])] = []
        for (dirname, patterns) in dirs {
            var files: [(String, Data)] = []
            for pattern in patterns {
                let matches = try expandSources([pattern], underBuild: true)
                for m in matches.sorted() {
                    let stem = ((m as NSString).lastPathComponent as NSString).deletingPathExtension
                    let data = try Data(contentsOf: URL(fileURLWithPath: m))
                    files.append((stem, data))
                }
            }
            var seen = Set<String>()
            files = files.filter { seen.insert($0.0).inserted }
            directories.append((dirname, files))
        }
        let image = Runix2MG.build(.init(boot: bootData, rootFiles: rootFiles, directories: directories))
        let finalOut: String
        if out.hasPrefix("/") {
            finalOut = out
        } else if out.hasPrefix(config.buildDir + "/") || out == config.buildDir {
            finalOut = abs(out)
        } else {
            finalOut = abs("\(config.buildDir)/\(out)")
        }
        mkdirp((finalOut as NSString).deletingLastPathComponent)
        try image.write(to: URL(fileURLWithPath: finalOut))
        return finalOut
    }

    // MARK: - Helpers

    private func abs(_ rel: String) -> String {
        if rel.hasPrefix("/") { return rel }
        return (projectRoot as NSString).appendingPathComponent(rel)
    }

    private func mkdirp(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true)
    }

    private func expandSources(_ patterns: [String], underBuild: Bool = false) throws -> [String] {
        var result: [String] = []
        let base = underBuild ? abs(config.buildDir) : projectRoot
        for pattern in patterns {
            if pattern.contains("*") || pattern.contains("?") {
                let ns = pattern as NSString
                let dirPart = ns.deletingLastPathComponent
                let filePat = ns.lastPathComponent
                let dir = dirPart.isEmpty || dirPart == "."
                    ? base
                    : (underBuild ? abs("\(config.buildDir)/\(dirPart)") : abs(dirPart))
                let files = try FileManager.default.contentsOfDirectory(atPath: dir)
                let matched = files.filter { matchesGlob(filePat, $0) }.sorted()
                for f in matched {
                    result.append((dir as NSString).appendingPathComponent(f))
                }
            } else {
                let path = underBuild ? abs("\(config.buildDir)/\(pattern)") : abs(pattern)
                if FileManager.default.fileExists(atPath: path) {
                    result.append(path)
                } else {
                    throw BuildError.io("source not found: \(pattern)")
                }
            }
        }
        return result
    }

    private func matchesGlob(_ pattern: String, _ name: String) -> Bool {
        // Minimal * support
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            return name.hasSuffix(String(pattern.dropFirst()))
        }
        return pattern == name
    }
}

/// JavaScriptCore host for generate steps.
enum JSGenerate {
    static func run(source: String, projectRoot: String) throws -> String {
        #if canImport(JavaScriptCore)
        guard let ctx = JSContext() else {
            throw BuildError.stepFailed("JavaScriptCore unavailable")
        }
        var stdout = ""
        ctx.exceptionHandler = { _, exc in
            stderrPrint("JS: \(exc?.toString() ?? "error")")
        }
        let printFn: @convention(block) (JSValue) -> Void = { args in
            // Called as print(...) — in JSC bridge we expose differently
            _ = args
        }
        _ = printFn
        // Simpler API: inject functions
        ctx.evaluateScript("""
        var __stdout = '';
        function print() {
          for (var i = 0; i < arguments.length; i++) {
            __stdout += String(arguments[i]);
          }
        }
        var console = { log: function() { print.apply(null, arguments); print('\\n'); } };
        """)
        let readFn: @convention(block) (String) -> String = { path in
            let full = path.hasPrefix("/") ? path : (projectRoot as NSString).appendingPathComponent(path)
            return (try? String(contentsOfFile: full, encoding: .utf8)) ?? ""
        }
        ctx.setObject(readFn, forKeyedSubscript: "read" as NSString)

        ctx.evaluateScript(source)
        if let exc = ctx.exception {
            throw BuildError.stepFailed("JS error: \(exc)")
        }
        stdout = ctx.evaluateScript("__stdout")?.toString() ?? ""
        return stdout
        #else
        throw BuildError.stepFailed("JavaScriptCore not available on this platform")
        #endif
    }
}

private func stderrPrint(_ s: String) {
    fputs(s + "\n", stderr)
}
