//
//  InMemoryFileSystem.swift
//  RotoskopWorkspace
//
//  A pure in-memory FileSystem used for tests and previews. No Foundation, no
//  disk — which is exactly what lets the file-browser logic run under
//  `swift test` on Linux.
//

/// An in-memory file system backed by a flat dictionary of paths to bytes.
public final class InMemoryFileSystem: FileSystem {
    private var files: [WorkspacePath: [UInt8]] = [:]
    private var directories: Set<WorkspacePath> = [.root]

    public init() {}

    public func exists(_ path: WorkspacePath) -> Bool {
        directories.contains(path) || files[path] != nil
    }

    public func isDirectory(_ path: WorkspacePath) -> Bool {
        directories.contains(path)
    }

    public func list(_ path: WorkspacePath) throws -> [FileEntry] {
        guard directories.contains(path) else {
            if files[path] != nil { throw FileSystemError.notADirectory(path) }
            throw FileSystemError.notFound(path)
        }
        var entries: [FileEntry] = []
        for dir in directories where dir.parent == path && dir != path {
            entries.append(FileEntry(path: dir, kind: .directory))
        }
        for (file, bytes) in files where file.parent == path {
            entries.append(FileEntry(path: file, kind: .file, size: bytes.count))
        }
        return entries.sorted { $0.name < $1.name }
    }

    public func createDirectory(_ path: WorkspacePath) throws {
        if exists(path) { throw FileSystemError.alreadyExists(path) }
        // Create intermediate directories too.
        var current = WorkspacePath.root
        for component in path.components {
            current = current.appending(component)
            if files[current] != nil { throw FileSystemError.notADirectory(current) }
            directories.insert(current)
        }
    }

    public func readFile(_ path: WorkspacePath) throws -> [UInt8] {
        if directories.contains(path) { throw FileSystemError.isADirectory(path) }
        guard let bytes = files[path] else { throw FileSystemError.notFound(path) }
        return bytes
    }

    public func writeFile(_ path: WorkspacePath, bytes: [UInt8]) throws {
        if directories.contains(path) { throw FileSystemError.isADirectory(path) }
        if !path.parent.isRoot && !directories.contains(path.parent) {
            try createDirectory(path.parent)
        }
        files[path] = bytes
    }

    public func remove(_ path: WorkspacePath) throws {
        if files[path] != nil {
            files[path] = nil
            return
        }
        guard directories.contains(path) else { throw FileSystemError.notFound(path) }
        directories = directories.filter { !$0.components.starts(with: path.components) }
        for file in files.keys where file.components.starts(with: path.components) {
            files[file] = nil
        }
    }

    public func move(from source: WorkspacePath, to destination: WorkspacePath) throws {
        if let bytes = files[source] {
            try writeFile(destination, bytes: bytes)
            files[source] = nil
        } else if directories.contains(source) {
            try createDirectory(destination)
            for file in files.keys where file.components.starts(with: source.components) {
                let suffix = Array(file.components.dropFirst(source.components.count))
                let newPath = WorkspacePath(components: destination.components + suffix)
                try writeFile(newPath, bytes: files[file]!)
            }
            try remove(source)
        } else {
            throw FileSystemError.notFound(source)
        }
    }
}
