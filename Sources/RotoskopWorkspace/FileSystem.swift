//
//  FileSystem.swift
//  RotoskopWorkspace
//
//  Abstracts file-system access behind a protocol so the file-browser logic can
//  be unit-tested on Linux with an in-memory implementation, while the app uses
//  a Foundation-backed one on device.
//

/// A path within a workspace, always relative to the repository root and using
/// `/` as the separator regardless of platform.
public struct WorkspacePath: Hashable, Sendable, CustomStringConvertible {
    public let components: [String]

    public init(components: [String]) {
        self.components = components.filter { !$0.isEmpty && $0 != "." }
    }

    public init(_ string: String) {
        self.init(components: string.split(separator: "/").map(String.init))
    }

    public static let root = WorkspacePath(components: [])

    public var isRoot: Bool { components.isEmpty }
    public var name: String { components.last ?? "" }
    public var parent: WorkspacePath { WorkspacePath(components: Array(components.dropLast())) }

    public func appending(_ component: String) -> WorkspacePath {
        WorkspacePath(components: components + [component])
    }

    public var string: String { components.joined(separator: "/") }
    public var description: String { "/" + string }
}

/// A single entry in a directory listing.
public struct FileEntry: Hashable, Sendable {
    public enum Kind: Sendable { case file, directory }
    public let path: WorkspacePath
    public let kind: Kind
    public let size: Int

    public init(path: WorkspacePath, kind: Kind, size: Int = 0) {
        self.path = path
        self.kind = kind
        self.size = size
    }

    public var isDirectory: Bool { kind == .directory }
    public var name: String { path.name }
}

/// Errors the file system can surface.
public enum FileSystemError: Error, Equatable {
    case notFound(WorkspacePath)
    case alreadyExists(WorkspacePath)
    case notADirectory(WorkspacePath)
    case isADirectory(WorkspacePath)
}

/// The operations the file browser needs. Deliberately small; concrete
/// implementations decide where the bytes actually live.
public protocol FileSystem: AnyObject {
    func exists(_ path: WorkspacePath) -> Bool
    func isDirectory(_ path: WorkspacePath) -> Bool
    func list(_ path: WorkspacePath) throws -> [FileEntry]
    func createDirectory(_ path: WorkspacePath) throws
    func readFile(_ path: WorkspacePath) throws -> [UInt8]
    func writeFile(_ path: WorkspacePath, bytes: [UInt8]) throws
    func remove(_ path: WorkspacePath) throws
    func move(from source: WorkspacePath, to destination: WorkspacePath) throws
}

public extension FileSystem {
    /// Reads a file as UTF-8 text.
    func readText(_ path: WorkspacePath) throws -> String {
        String(decoding: try readFile(path), as: UTF8.self)
    }

    /// Writes UTF-8 text to a file.
    func writeText(_ path: WorkspacePath, _ text: String) throws {
        try writeFile(path, bytes: Array(text.utf8))
    }
}
