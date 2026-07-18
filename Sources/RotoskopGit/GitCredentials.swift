import Foundation
import libgit2

/// Bridges a PAT into libgit2 credential callbacks for HTTPS GitHub remotes.
final class GitCredentialBridge: @unchecked Sendable {
    let token: String
    private let lock = NSLock()

    init(token: String) {
        self.token = token
    }

    /// Payload for C callbacks; caller must keep this instance alive for the call.
    var unmanagedPayload: UnsafeMutableRawPointer {
        Unmanaged.passUnretained(self).toOpaque()
    }

    static let credentialsCallback: git_credential_acquire_cb = { cred, _, _, _, payload in
        guard let payload else { return -1 }
        let bridge = Unmanaged<GitCredentialBridge>.fromOpaque(payload).takeUnretainedValue()
        // GitHub HTTPS PAT: username `x-access-token`, password = token.
        return git_credential_userpass_plaintext_new(
            cred,
            "x-access-token",
            bridge.token
        )
    }
}

enum GitURL {
    /// Normalize a GitHub HTTPS URL. Rejects SSH for v1.
    static func normalizeHTTPS(_ raw: String) throws -> URL {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitError(.invalidURL(raw)) }

        // Reject SCP-style and ssh:// remotes (v1 is HTTPS + PAT only).
        if trimmed.hasPrefix("git@") || trimmed.hasPrefix("ssh://") {
            throw GitError(.invalidURL("Only HTTPS remotes are supported in v1"))
        }

        var candidate = trimmed

        // Accept github.com/owner/repo shorthand.
        if !candidate.contains("://"), candidate.hasPrefix("github.com/") {
            candidate = "https://\(candidate)"
        }
        if !candidate.contains("://"),
           candidate.split(separator: "/").count == 2,
           !candidate.contains("@")
        {
            candidate = "https://github.com/\(candidate)"
        }

        guard var components = URLComponents(string: candidate) else {
            throw GitError(.invalidURL(raw))
        }
        if components.scheme == nil {
            components.scheme = "https"
        }
        guard components.scheme == "https" else {
            throw GitError(.invalidURL("Only HTTPS remotes are supported in v1 (got \(components.scheme ?? "nil"))"))
        }
        guard let host = components.host, host.contains("github.com") else {
            throw GitError(.invalidURL("Remotes must be GitHub HTTPS in v1"))
        }
        guard let url = components.url else {
            throw GitError(.invalidURL(raw))
        }
        return url
    }

    static func suggestedDirectoryName(from url: URL) -> String {
        var last = url.lastPathComponent
        if last.hasSuffix(".git") {
            last = String(last.dropLast(4))
        }
        return last.isEmpty ? "repo" : last
    }
}
