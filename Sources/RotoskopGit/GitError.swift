import Foundation
import libgit2

/// Errors from Rotoskop Git operations.
public struct GitError: Error, LocalizedError, Equatable, Sendable {
    public enum Kind: Equatable, Sendable {
        case libgit2(code: Int32, message: String)
        case notARepository
        case invalidURL(String)
        case missingCredentials
        case mergeConflict
        case nothingToCommit
        case branchNotFound(String)
        case projectExists(String)
        case projectNotFound(String)
        case other(String)
    }

    public let kind: Kind

    public init(_ kind: Kind) {
        self.kind = kind
    }

    public var errorDescription: String? {
        switch kind {
        case .libgit2(_, let message):
            return message.isEmpty ? "Git operation failed" : message
        case .notARepository:
            return "Not a Git repository"
        case .invalidURL(let url):
            return "Invalid Git URL: \(url)"
        case .missingCredentials:
            return "GitHub personal access token is not set"
        case .mergeConflict:
            return "Merge aborted: conflicts detected. Repository left unchanged."
        case .nothingToCommit:
            return "Nothing to commit"
        case .branchNotFound(let name):
            return "Branch not found: \(name)"
        case .projectExists(let name):
            return "Project already exists: \(name)"
        case .projectNotFound(let name):
            return "Project not found: \(name)"
        case .other(let message):
            return message
        }
    }

    static func lastLibGit2(code: Int32) -> GitError {
        let message: String
        if let cstr = git_error_last()?.pointee.message {
            message = String(cString: cstr)
        } else {
            message = "libgit2 error \(code)"
        }
        return GitError(.libgit2(code: code, message: message))
    }

    static func check(_ code: Int32) throws {
        guard code >= 0 else { throw lastLibGit2(code: code) }
    }
}
