import Foundation

/// A known project (app-managed clone).
public struct ProjectRecord: Codable, Equatable, Hashable, Identifiable, Sendable {
    public var id: String
    /// Display name (usually the repo folder name).
    public var name: String
    /// HTTPS remote URL used to clone.
    public var remoteURL: String
    /// Directory name under the projects root (not a full path).
    public var directoryName: String
    public var clonedAt: Date

    public init(
        id: String = UUID().uuidString,
        name: String,
        remoteURL: String,
        directoryName: String,
        clonedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.remoteURL = remoteURL
        self.directoryName = directoryName
        self.clonedAt = clonedAt
    }
}

/// Simplified working-tree status for commit UI.
public struct GitFileStatus: Equatable, Identifiable, Sendable {
    public enum Kind: String, Equatable, Sendable {
        case modified
        case added
        case deleted
        case renamed
        case untracked
        case conflicted
        case other
    }

    public var id: String { path }
    public let path: String
    public let kind: Kind

    public init(path: String, kind: Kind) {
        self.path = path
        self.kind = kind
    }
}

public struct GitStatus: Equatable, Sendable {
    public let branch: String?
    public let files: [GitFileStatus]
    public var isClean: Bool { files.isEmpty }

    public init(branch: String?, files: [GitFileStatus]) {
        self.branch = branch
        self.files = files
    }
}

public struct GitCommitResult: Equatable, Sendable {
    public let oid: String
    public let message: String

    public init(oid: String, message: String) {
        self.oid = oid
        self.message = message
    }
}

public enum GitMergeResult: Equatable, Sendable {
    case upToDate
    case fastForward(oid: String)
    case merged(oid: String)
}
