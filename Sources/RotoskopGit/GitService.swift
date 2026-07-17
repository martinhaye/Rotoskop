//
//  GitService.swift
//  RotoskopGit
//
//  Protocol + value types for the repo list and sync features. Only the
//  abstraction lives here so it stays Linux-testable; the concrete
//  implementation (libgit2 / SwiftGit2, or shelling out to git) is provided by
//  the app layer and injected. Tests use fakes conforming to `GitService`.
//

/// A configured remote repository the user has added to Rotoskop.
public struct Repository: Hashable, Sendable, Identifiable {
    public let id: String
    public var displayName: String
    public var remoteURL: String
    public var defaultBranch: String
    /// Local checkout location, expressed as an opaque token the app maps to a
    /// real directory (kept opaque so this module needs no Foundation).
    public var localSlug: String

    public init(id: String,
                displayName: String,
                remoteURL: String,
                defaultBranch: String = "main",
                localSlug: String) {
        self.id = id
        self.displayName = displayName
        self.remoteURL = remoteURL
        self.defaultBranch = defaultBranch
        self.localSlug = localSlug
    }
}

/// The working-tree/sync state of a repository, for display in the repo list.
public struct SyncStatus: Hashable, Sendable {
    public var currentBranch: String
    public var hasLocalChanges: Bool
    public var ahead: Int
    public var behind: Int

    public init(currentBranch: String,
                hasLocalChanges: Bool = false,
                ahead: Int = 0,
                behind: Int = 0) {
        self.currentBranch = currentBranch
        self.hasLocalChanges = hasLocalChanges
        self.ahead = ahead
        self.behind = behind
    }

    public var isClean: Bool { !hasLocalChanges && ahead == 0 && behind == 0 }
}

/// Credentials used for authenticated remotes. The app is responsible for
/// sourcing these securely (e.g. Keychain); this module only passes them along.
public struct GitCredentials: Sendable {
    public var username: String
    public var token: String
    public init(username: String, token: String) {
        self.username = username
        self.token = token
    }
}

public enum GitError: Error, Equatable {
    case notCloned
    case authenticationRequired
    case conflict(String)
    case remoteUnavailable
    case underlying(String)
}

/// The git operations the UI needs. Async so implementations can perform I/O
/// off the main actor.
public protocol GitService: AnyObject {
    func clone(_ repository: Repository, credentials: GitCredentials?) async throws
    func status(_ repository: Repository) async throws -> SyncStatus
    func pull(_ repository: Repository, credentials: GitCredentials?) async throws -> SyncStatus
    func push(_ repository: Repository, credentials: GitCredentials?) async throws -> SyncStatus
    func commitAll(_ repository: Repository, message: String) async throws
}
