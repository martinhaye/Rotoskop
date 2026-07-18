import Foundation

/// Project tree listing and file CRUD for the Files tab (DESIGN §2).
/// Hides `.git/`; shows `build/` and other entries.
public enum ProjectFileSystem {
    public struct Node: Identifiable, Equatable, Sendable {
        public var id: String { relativePath }
        public var name: String
        public var relativePath: String
        public var isDirectory: Bool
        public var children: [Node]

        public init(name: String, relativePath: String, isDirectory: Bool, children: [Node] = []) {
            self.name = name
            self.relativePath = relativePath
            self.isDirectory = isDirectory
            self.children = children
        }
    }

    public enum Error: Swift.Error, LocalizedError, Equatable {
        case invalidName(String)
        case notFound(String)
        case alreadyExists(String)
        case notUnderRoot(String)
        case isDirectory(String)
        case notDirectory(String)

        public var errorDescription: String? {
            switch self {
            case .invalidName(let name): return "Invalid name: \(name)"
            case .notFound(let path): return "Not found: \(path)"
            case .alreadyExists(let path): return "Already exists: \(path)"
            case .notUnderRoot(let path): return "Path escapes project root: \(path)"
            case .isDirectory(let path): return "Expected a file: \(path)"
            case .notDirectory(let path): return "Expected a directory: \(path)"
            }
        }
    }

    /// Recursively list the project tree, skipping `.git` directories.
    public static func listTree(
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> [Node] {
        let root = rootURL.standardizedFileURL
        guard fileManager.fileExists(atPath: root.path) else {
            throw Error.notFound(root.path)
        }
        return try listChildren(of: root, relativePrefix: "", fileManager: fileManager)
    }

    public static func resolve(
        rootURL: URL,
        relativePath: String,
        fileManager: FileManager = .default
    ) throws -> URL {
        let url = try absolutize(rootURL: rootURL, relativePath: relativePath)
        guard fileManager.fileExists(atPath: url.path) else {
            throw Error.notFound(relativePath)
        }
        return url
    }

    public static func readText(
        rootURL: URL,
        relativePath: String,
        fileManager: FileManager = .default
    ) throws -> String {
        let url = try resolve(rootURL: rootURL, relativePath: relativePath, fileManager: fileManager)
        var isDir: ObjCBool = false
        guard fileManager.fileExists(atPath: url.path, isDirectory: &isDir), !isDir.boolValue else {
            throw Error.isDirectory(relativePath)
        }
        return try String(contentsOf: url, encoding: .utf8)
    }

    public static func writeText(
        _ text: String,
        rootURL: URL,
        relativePath: String,
        fileManager: FileManager = .default
    ) throws {
        let url = try absolutize(rootURL: rootURL, relativePath: relativePath)
        let parent = url.deletingLastPathComponent()
        try fileManager.createDirectory(at: parent, withIntermediateDirectories: true)
        try text.write(to: url, atomically: true, encoding: .utf8)
    }

    public static func createFile(
        named name: String,
        inDirectory relativeDirectory: String,
        rootURL: URL,
        contents: String = "",
        fileManager: FileManager = .default
    ) throws -> String {
        let fileName = try validateName(name)
        let relativePath = join(relativeDirectory, fileName)
        let url = try absolutize(rootURL: rootURL, relativePath: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            throw Error.alreadyExists(relativePath)
        }
        try fileManager.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return relativePath
    }

    public static func createDirectory(
        named name: String,
        inDirectory relativeDirectory: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws -> String {
        let dirName = try validateName(name)
        let relativePath = join(relativeDirectory, dirName)
        let url = try absolutize(rootURL: rootURL, relativePath: relativePath)
        if fileManager.fileExists(atPath: url.path) {
            throw Error.alreadyExists(relativePath)
        }
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return relativePath
    }

    /// Rename or move within the project (`newRelativePath` is the full new relative path).
    public static func move(
        from relativePath: String,
        to newRelativePath: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let source = try resolve(rootURL: rootURL, relativePath: relativePath, fileManager: fileManager)
        let dest = try absolutize(rootURL: rootURL, relativePath: newRelativePath)
        if fileManager.fileExists(atPath: dest.path) {
            throw Error.alreadyExists(newRelativePath)
        }
        try fileManager.createDirectory(
            at: dest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try fileManager.moveItem(at: source, to: dest)
    }

    public static func delete(
        relativePath: String,
        rootURL: URL,
        fileManager: FileManager = .default
    ) throws {
        let url = try resolve(rootURL: rootURL, relativePath: relativePath, fileManager: fileManager)
        try fileManager.removeItem(at: url)
    }

    public static func isAssemblyFile(_ relativePath: String) -> Bool {
        let ext = (relativePath as NSString).pathExtension.lowercased()
        return ext == "s" || ext == "i"
    }

    // MARK: - Internals

    private static func listChildren(
        of directory: URL,
        relativePrefix: String,
        fileManager: FileManager
    ) throws -> [Node] {
        let contents = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey, .isSymbolicLinkKey],
            options: []
        )
        var nodes: [Node] = []
        for url in contents.sorted(by: { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }) {
            let name = url.lastPathComponent
            if name == ".git" { continue }
            let relativePath = relativePrefix.isEmpty ? name : "\(relativePrefix)/\(name)"
            let values = try url.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            let isDir = values.isDirectory == true && values.isSymbolicLink != true
            if isDir {
                let kids = try listChildren(of: url, relativePrefix: relativePath, fileManager: fileManager)
                nodes.append(Node(name: name, relativePath: relativePath, isDirectory: true, children: kids))
            } else {
                nodes.append(Node(name: name, relativePath: relativePath, isDirectory: false))
            }
        }
        return nodes
    }

    private static func validateName(_ name: String) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              !trimmed.contains("/"),
              trimmed != ".",
              trimmed != "..",
              trimmed != ".git"
        else {
            throw Error.invalidName(name)
        }
        return trimmed
    }

    private static func join(_ directory: String, _ name: String) -> String {
        let dir = directory.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if dir.isEmpty { return name }
        return "\(dir)/\(name)"
    }

    private static func absolutize(rootURL: URL, relativePath: String) throws -> URL {
        let root = rootURL.standardizedFileURL
        let cleaned = relativePath
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." }
        if cleaned.contains("..") || cleaned.contains(".git") {
            throw Error.notUnderRoot(relativePath)
        }
        var url = root
        for part in cleaned {
            url = url.appendingPathComponent(part, isDirectory: false)
        }
        let standardized = url.standardizedFileURL
        let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
        let candidate = standardized.path
        if candidate != root.path && !candidate.hasPrefix(rootPath) {
            throw Error.notUnderRoot(relativePath)
        }
        return standardized
    }
}
