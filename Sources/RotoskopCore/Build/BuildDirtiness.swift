import Foundation

/// Dirty check for Run→build (DESIGN §7.2): sources/config newer than last successful build stamp.
public enum BuildDirtiness {
    public static let stampFileName = ".rotoskop-built"

    public static func stampPath(projectRoot: String, config: ProjectConfig) -> String {
        let root = (projectRoot as NSString).standardizingPath
        let buildDir = config.buildDir.hasPrefix("/")
            ? config.buildDir
            : (root as NSString).appendingPathComponent(config.buildDir)
        return (buildDir as NSString).appendingPathComponent(stampFileName)
    }

    public static func markBuilt(
        projectRoot: String,
        config: ProjectConfig,
        fileManager: FileManager = .default
    ) throws {
        let path = stampPath(projectRoot: projectRoot, config: config)
        let dir = (path as NSString).deletingLastPathComponent
        try fileManager.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let stamp = "\(ISO8601DateFormatter().string(from: Date()))\n"
        try stamp.write(toFile: path, atomically: true, encoding: .utf8)
    }

    /// True when a rebuild is needed before Run.
    public static func isDirty(
        projectRoot: String,
        config: ProjectConfig,
        fileManager: FileManager = .default
    ) -> Bool {
        let stamp = stampPath(projectRoot: projectRoot, config: config)
        guard let stampDate = modificationDate(of: stamp, fileManager: fileManager) else {
            return true
        }
        let inputs = inputPaths(projectRoot: projectRoot, config: config, fileManager: fileManager)
        for path in inputs {
            if let date = modificationDate(of: path, fileManager: fileManager), date > stampDate {
                return true
            }
        }
        return false
    }

    public static func inputPaths(
        projectRoot: String,
        config: ProjectConfig,
        fileManager: FileManager = .default
    ) -> [String] {
        let root = (projectRoot as NSString).standardizingPath
        func abs(_ rel: String) -> String {
            rel.hasPrefix("/") ? rel : (root as NSString).appendingPathComponent(rel)
        }

        var paths: [String] = [abs("rotoskop.yaml")]
        for step in config.steps {
            switch step {
            case .generate(_, let script, _):
                paths.append(abs(script))
            case .assemble(let sources, _, _):
                paths.append(contentsOf: expand(sources, root: root, fileManager: fileManager))
            case .packImage:
                break
            }
        }
        // Include dirs: any change under include paths can affect assemble output.
        for dir in config.includeDirs {
            paths.append(contentsOf: listFilesRecursively(abs(dir), fileManager: fileManager))
        }
        return Array(Set(paths)).sorted()
    }

    private static func expand(
        _ patterns: [String],
        root: String,
        fileManager: FileManager
    ) -> [String] {
        var result: [String] = []
        for pattern in patterns {
            if pattern.contains("*") || pattern.contains("?") {
                let ns = pattern as NSString
                let dirPart = ns.deletingLastPathComponent
                let filePat = ns.lastPathComponent
                let dir = dirPart.isEmpty || dirPart == "."
                    ? root
                    : (root as NSString).appendingPathComponent(dirPart)
                guard let files = try? fileManager.contentsOfDirectory(atPath: dir) else { continue }
                for f in files where matchesGlob(filePat, f) {
                    result.append((dir as NSString).appendingPathComponent(f))
                }
            } else {
                let path = pattern.hasPrefix("/")
                    ? pattern
                    : (root as NSString).appendingPathComponent(pattern)
                if fileManager.fileExists(atPath: path) {
                    result.append(path)
                }
            }
        }
        return result
    }

    private static func listFilesRecursively(_ directory: String, fileManager: FileManager) -> [String] {
        guard fileManager.fileExists(atPath: directory) else { return [] }
        guard let enumerator = fileManager.enumerator(atPath: directory) else { return [] }
        var result: [String] = []
        for case let relative as String in enumerator {
            if relative.contains(".git/") { continue }
            let full = (directory as NSString).appendingPathComponent(relative)
            var isDir: ObjCBool = false
            if fileManager.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue {
                result.append(full)
            }
        }
        return result
    }

    private static func matchesGlob(_ pattern: String, _ name: String) -> Bool {
        if pattern == "*" { return true }
        if pattern.hasPrefix("*.") {
            return name.hasSuffix(String(pattern.dropFirst()))
        }
        return pattern == name
    }

    private static func modificationDate(of path: String, fileManager: FileManager) -> Date? {
        let attrs = try? fileManager.attributesOfItem(atPath: path)
        return attrs?[.modificationDate] as? Date
    }
}
