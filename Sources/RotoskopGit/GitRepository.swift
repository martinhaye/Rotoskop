import Foundation
import libgit2

/// Thin libgit2 wrapper for DESIGN §1 Git ops.
public final class GitRepository: @unchecked Sendable {
    public let workingDirectory: URL
    private let repo: OpaquePointer
    private let patStore: any PATStore

    public init(opening path: URL, patStore: any PATStore = KeychainPATStore()) throws {
        GitRuntime.initialize()
        self.workingDirectory = path.standardizedFileURL
        self.patStore = patStore
        var pointer: OpaquePointer?
        let code = path.path.withCString { git_repository_open(&pointer, $0) }
        guard code == 0, let pointer else {
            GitRuntime.shutdown()
            throw GitError.lastLibGit2(code: code == 0 ? -1 : code)
        }
        self.repo = pointer
    }

    deinit {
        git_repository_free(repo)
        GitRuntime.shutdown()
    }

    // MARK: - Clone

    public static func clone(
        from remoteURL: String,
        to destination: URL,
        patStore: any PATStore = KeychainPATStore()
    ) async throws -> GitRepository {
        let url = try GitURL.normalizeHTTPS(remoteURL)
        let token = try await Task.detached {
            try patStore.load()
        }.value
        guard let token, !token.isEmpty else {
            throw GitError(.missingCredentials)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        if FileManager.default.fileExists(atPath: destination.path) {
            throw GitError(.other("Destination already exists: \(destination.path)"))
        }

        return try await Task.detached(priority: .userInitiated) {
            GitRuntime.initialize()
            defer { GitRuntime.shutdown() }

            let bridge = GitCredentialBridge(token: token)
            var options = git_clone_options()
            try GitError.check(git_clone_options_init(&options, UInt32(GIT_CLONE_OPTIONS_VERSION)))
            options.checkout_opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
            options.fetch_opts.callbacks.credentials = GitCredentialBridge.credentialsCallback
            options.fetch_opts.callbacks.payload = bridge.unmanagedPayload

            var pointer: OpaquePointer?
            let code = git_clone(
                &pointer,
                url.absoluteString,
                destination.path,
                &options
            )
            guard code == 0, let pointer else {
                throw GitError.lastLibGit2(code: code)
            }
            git_repository_free(pointer)
            let repository = try GitRepository(opening: destination, patStore: patStore)
            // DESIGN: clones track `rotoskop` when that remote branch exists.
            if (try? repository.listBranches())?.contains("rotoskop") == true,
               (try? repository.currentBranchName()) != "rotoskop"
            {
                try repository.switchBranch("rotoskop")
            }
            return repository
        }.value
    }

    // MARK: - Status / branch

    public func currentBranchName() throws -> String? {
        var head: OpaquePointer?
        let code = git_repository_head(&head, repo)
        defer { git_reference_free(head) }
        if code == GIT_EUNBORNBRANCH.rawValue || code == GIT_ENOTFOUND.rawValue {
            return nil
        }
        try GitError.check(code)
        guard let head, git_reference_is_branch(head) == 1 else { return nil }
        guard let name = git_reference_shorthand(head) else { return nil }
        return String(cString: name)
    }

    public func status() throws -> GitStatus {
        var opts = git_status_options()
        try GitError.check(git_status_options_init(&opts, UInt32(GIT_STATUS_OPTIONS_VERSION)))
        opts.flags = GIT_STATUS_OPT_INCLUDE_UNTRACKED.rawValue
            | GIT_STATUS_OPT_RENAMES_HEAD_TO_INDEX.rawValue
            | GIT_STATUS_OPT_RENAMES_INDEX_TO_WORKDIR.rawValue

        var list: OpaquePointer?
        try GitError.check(git_status_list_new(&list, repo, &opts))
        defer { git_status_list_free(list) }

        var files: [GitFileStatus] = []
        let count = git_status_list_entrycount(list)
        for i in 0..<count {
            guard let entry = git_status_byindex(list, i)?.pointee else { continue }
            let flags = entry.status.rawValue
            let path = Self.path(from: entry)
            guard let path else { continue }
            files.append(GitFileStatus(path: path, kind: Self.kind(for: flags)))
        }
        return GitStatus(branch: try currentBranchName(), files: files)
    }

    private static func path(from entry: git_status_entry) -> String? {
        if let delta = entry.head_to_index {
            if let p = delta.pointee.new_file.path { return String(cString: p) }
            if let p = delta.pointee.old_file.path { return String(cString: p) }
        }
        if let delta = entry.index_to_workdir {
            if let p = delta.pointee.new_file.path { return String(cString: p) }
            if let p = delta.pointee.old_file.path { return String(cString: p) }
        }
        return nil
    }

    private static func kind(for flags: UInt32) -> GitFileStatus.Kind {
        if flags & GIT_STATUS_CONFLICTED.rawValue != 0 { return .conflicted }
        if flags & GIT_STATUS_WT_NEW.rawValue != 0 { return .untracked }
        if flags & (GIT_STATUS_INDEX_NEW.rawValue) != 0 { return .added }
        if flags & (GIT_STATUS_INDEX_DELETED.rawValue | GIT_STATUS_WT_DELETED.rawValue) != 0 {
            return .deleted
        }
        if flags & (GIT_STATUS_INDEX_RENAMED.rawValue | GIT_STATUS_WT_RENAMED.rawValue) != 0 {
            return .renamed
        }
        if flags
            & (GIT_STATUS_INDEX_MODIFIED.rawValue | GIT_STATUS_WT_MODIFIED.rawValue
                | GIT_STATUS_WT_TYPECHANGE.rawValue | GIT_STATUS_INDEX_TYPECHANGE.rawValue) != 0
        {
            return .modified
        }
        return .other
    }

    /// Local branch names plus remote-tracking short names (e.g. `origin/rotoskop` → `rotoskop`).
    public func listBranches() throws -> [String] {
        var iterator: OpaquePointer?
        try GitError.check(git_branch_iterator_new(&iterator, repo, GIT_BRANCH_ALL))
        defer { git_branch_iterator_free(iterator) }

        var names = Set<String>()
        while true {
            var ref: OpaquePointer?
            var type = GIT_BRANCH_LOCAL
            let code = git_branch_next(&ref, &type, iterator)
            if code == GIT_ITEROVER.rawValue { break }
            try GitError.check(code)
            defer { git_reference_free(ref) }
            var namePtr: UnsafePointer<CChar>?
            try GitError.check(git_branch_name(&namePtr, ref))
            guard let namePtr else { continue }
            let raw = String(cString: namePtr)
            if type == GIT_BRANCH_REMOTE {
                guard let short = Self.shortName(fromRemoteTracking: raw) else { continue }
                names.insert(short)
            } else {
                names.insert(raw)
            }
        }
        return names.sorted()
    }

    /// `origin/feature` → `feature`; skips symbolic `origin/HEAD`.
    private static func shortName(fromRemoteTracking raw: String) -> String? {
        guard let slash = raw.firstIndex(of: "/") else { return nil }
        let short = String(raw[raw.index(after: slash)...])
        guard !short.isEmpty, short != "HEAD" else { return nil }
        return short
    }

    // MARK: - Commit

    /// Stage all changes (v1: commit-all) and commit with message.
    @discardableResult
    public func commitAll(message: String, authorName: String, authorEmail: String) throws -> GitCommitResult {
        let trimmed = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw GitError(.other("Commit message is empty")) }

        var index: OpaquePointer?
        try GitError.check(git_repository_index(&index, repo))
        defer { git_index_free(index) }

        try GitError.check(git_index_add_all(index, nil, 0, nil, nil))
        try GitError.check(git_index_write(index))

        var treeOID = git_oid()
        try GitError.check(git_index_write_tree(&treeOID, index))

        var tree: OpaquePointer?
        try GitError.check(git_tree_lookup(&tree, repo, &treeOID))
        defer { git_tree_free(tree) }

        var parent: OpaquePointer?
        var parentCount: Int = 0
        var head: OpaquePointer?
        let headCode = git_repository_head(&head, repo)
        if headCode == 0, let head {
            defer { git_reference_free(head) }
            try GitError.check(git_reference_peel(&parent, head, GIT_OBJECT_COMMIT))
            parentCount = 1
        } else if headCode != GIT_EUNBORNBRANCH.rawValue && headCode != GIT_ENOTFOUND.rawValue {
            try GitError.check(headCode)
        }

        defer { if parentCount > 0 { git_commit_free(parent) } }

        // Skip empty commits when we have a parent with the same tree.
        if parentCount == 1, let parent {
            let parentTreeOID = git_commit_tree_id(parent)
            if git_oid_equal(&treeOID, parentTreeOID) == 1 {
                throw GitError(.nothingToCommit)
            }
        }

        var signature: UnsafeMutablePointer<git_signature>?
        try GitError.check(git_signature_now(&signature, authorName, authorEmail))
        defer { git_signature_free(signature) }

        var commitOID = git_oid()
        var parents: [OpaquePointer?] = parentCount == 1 ? [parent] : []
        try parents.withUnsafeMutableBufferPointer { buffer in
            try GitError.check(
                git_commit_create(
                    &commitOID,
                    repo,
                    "HEAD",
                    signature,
                    signature,
                    nil,
                    trimmed,
                    tree,
                    parentCount,
                    buffer.baseAddress
                )
            )
        }

        var oid = commitOID
        return GitCommitResult(oid: Self.oidString(&oid), message: trimmed)
    }

    // MARK: - Branch

    public func createBranch(_ name: String, checkout: Bool = true) throws {
        var head: OpaquePointer?
        try GitError.check(git_repository_head(&head, repo))
        defer { git_reference_free(head) }

        var commit: OpaquePointer?
        try GitError.check(git_reference_peel(&commit, head, GIT_OBJECT_COMMIT))
        defer { git_commit_free(commit) }

        var branch: OpaquePointer?
        try GitError.check(git_branch_create(&branch, repo, name, commit, 0))
        defer { git_reference_free(branch) }

        if checkout {
            try switchBranch(name)
        }
    }

    public func switchBranch(_ name: String) throws {
        var branch: OpaquePointer?
        let find = git_branch_lookup(&branch, repo, name, GIT_BRANCH_LOCAL)
        if find == 0, let branch {
            defer { git_reference_free(branch) }
            try checkoutLocalBranch(branch)
            return
        }

        // No local branch: create one tracking a remote-tracking ref (e.g. origin/name).
        let remoteTracking = try findRemoteTrackingBranch(named: name)
        defer { git_reference_free(remoteTracking) }

        var commit: OpaquePointer?
        try GitError.check(git_reference_peel(&commit, remoteTracking, GIT_OBJECT_COMMIT))
        defer { git_commit_free(commit) }

        var local: OpaquePointer?
        try GitError.check(git_branch_create(&local, repo, name, commit, 0))
        defer { git_reference_free(local) }

        var remoteNamePtr: UnsafePointer<CChar>?
        try GitError.check(git_branch_name(&remoteNamePtr, remoteTracking))
        if let remoteNamePtr {
            _ = git_branch_set_upstream(local, remoteNamePtr)
        }

        try checkoutLocalBranch(local)
    }

    private func checkoutLocalBranch(_ branch: OpaquePointer?) throws {
        guard let branch, let refName = git_reference_name(branch) else {
            throw GitError(.other("Could not read branch ref name"))
        }

        var commit: OpaquePointer?
        try GitError.check(git_reference_peel(&commit, branch, GIT_OBJECT_COMMIT))
        defer { git_commit_free(commit) }

        // Checkout the tree *before* moving HEAD. set_head-first makes SAFE a no-op
        // (target == baseline while the workdir is still on the old branch).
        var opts = git_checkout_options()
        try GitError.check(git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
        opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        try GitError.check(git_checkout_tree(repo, commit, &opts))
        try GitError.check(git_repository_set_head(repo, refName))
    }

    /// Prefer `origin/<name>`, otherwise any remote-tracking branch ending in `/<name>`.
    private func findRemoteTrackingBranch(named name: String) throws -> OpaquePointer {
        let preferred = "origin/\(name)"
        var remote: OpaquePointer?
        if git_branch_lookup(&remote, repo, preferred, GIT_BRANCH_REMOTE) == 0, let remote {
            return remote
        }

        var iterator: OpaquePointer?
        try GitError.check(git_branch_iterator_new(&iterator, repo, GIT_BRANCH_REMOTE))
        defer { git_branch_iterator_free(iterator) }

        while true {
            var ref: OpaquePointer?
            var type = GIT_BRANCH_REMOTE
            let code = git_branch_next(&ref, &type, iterator)
            if code == GIT_ITEROVER.rawValue { break }
            try GitError.check(code)
            var namePtr: UnsafePointer<CChar>?
            try GitError.check(git_branch_name(&namePtr, ref))
            if let namePtr, Self.shortName(fromRemoteTracking: String(cString: namePtr)) == name {
                return ref!
            }
            git_reference_free(ref)
        }
        throw GitError(.branchNotFound(name))
    }

    // MARK: - Fetch / Push / Pull / Merge

    public func fetch(remoteName: String = "origin") async throws {
        let token = try requireToken()
        try await Task.detached(priority: .userInitiated) { [repo] in
            let bridge = GitCredentialBridge(token: token)
            var remote: OpaquePointer?
            try GitError.check(git_remote_lookup(&remote, repo, remoteName))
            defer { git_remote_free(remote) }

            var callbacks = git_remote_callbacks()
            try GitError.check(git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION)))
            callbacks.credentials = GitCredentialBridge.credentialsCallback
            callbacks.payload = bridge.unmanagedPayload

            var opts = git_fetch_options()
            try GitError.check(git_fetch_options_init(&opts, UInt32(GIT_FETCH_OPTIONS_VERSION)))
            opts.callbacks = callbacks

            try GitError.check(git_remote_fetch(remote, nil, &opts, nil))
        }.value
    }

    public func push(remoteName: String = "origin") async throws {
        let token = try requireToken()
        let branch = try currentBranchName()
        guard let branch else { throw GitError(.other("Detached HEAD; cannot push")) }

        try await Task.detached(priority: .userInitiated) { [repo] in
            let bridge = GitCredentialBridge(token: token)
            var remote: OpaquePointer?
            try GitError.check(git_remote_lookup(&remote, repo, remoteName))
            defer { git_remote_free(remote) }

            var callbacks = git_remote_callbacks()
            try GitError.check(git_remote_init_callbacks(&callbacks, UInt32(GIT_REMOTE_CALLBACKS_VERSION)))
            callbacks.credentials = GitCredentialBridge.credentialsCallback
            callbacks.payload = bridge.unmanagedPayload

            var opts = git_push_options()
            try GitError.check(git_push_options_init(&opts, UInt32(GIT_PUSH_OPTIONS_VERSION)))
            opts.callbacks = callbacks

            let refspec = "refs/heads/\(branch):refs/heads/\(branch)"
            let refspecCString = strdup(refspec)
            defer { free(refspecCString) }
            var strings: [UnsafeMutablePointer<CChar>?] = [refspecCString]
            try strings.withUnsafeMutableBufferPointer { buffer in
                var specs = git_strarray(strings: buffer.baseAddress, count: 1)
                try GitError.check(git_remote_push(remote, &specs, &opts))
            }
        }.value
    }

    /// Fetch + merge upstream (merge-only). Conflicts abort and leave the repo unchanged.
    public func pull(remoteName: String = "origin") async throws -> GitMergeResult {
        try await fetch(remoteName: remoteName)
        let branch = try currentBranchName()
        guard let branch else { throw GitError(.other("Detached HEAD; cannot pull")) }
        let upstream = "\(remoteName)/\(branch)"
        return try mergeClean(from: upstream)
    }

    /// Merge `refName` into HEAD only if clean (FF or auto-merge). Conflicts → abort.
    public func mergeClean(from refName: String) throws -> GitMergeResult {
        var theirRef: OpaquePointer?
        let lookup = git_reference_dwim(&theirRef, repo, refName)
        if lookup != 0 {
            // Try as remote branch ref.
            let full = refName.hasPrefix("refs/") ? refName : "refs/remotes/\(refName)"
            try GitError.check(git_reference_lookup(&theirRef, repo, full))
        }
        defer { git_reference_free(theirRef) }

        var theirCommit: OpaquePointer?
        try GitError.check(git_reference_peel(&theirCommit, theirRef, GIT_OBJECT_COMMIT))
        defer { git_commit_free(theirCommit) }

        var theirAnnotated: OpaquePointer?
        try GitError.check(git_annotated_commit_from_ref(&theirAnnotated, repo, theirRef))
        defer { git_annotated_commit_free(theirAnnotated) }

        var analysis = GIT_MERGE_ANALYSIS_NONE
        var preference = GIT_MERGE_PREFERENCE_NONE
        var heads: [OpaquePointer?] = [theirAnnotated]
        try heads.withUnsafeMutableBufferPointer { buffer in
            try GitError.check(
                git_merge_analysis(
                    &analysis,
                    &preference,
                    repo,
                    buffer.baseAddress,
                    1
                )
            )
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_UP_TO_DATE.rawValue != 0 {
            return .upToDate
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_FASTFORWARD.rawValue != 0 {
            return try fastForward(to: theirCommit)
        }

        if analysis.rawValue & GIT_MERGE_ANALYSIS_NORMAL.rawValue == 0 {
            throw GitError(.other("Cannot merge: unsupported analysis result"))
        }

        // Snapshot HEAD OID so we can restore on conflict.
        var headCommit: OpaquePointer?
        try GitError.check(git_revparse_single(&headCommit, repo, "HEAD"))
        defer { git_object_free(headCommit) }
        var headOID = git_object_id(headCommit)!.pointee

        do {
            try heads.withUnsafeMutableBufferPointer { buffer in
                try GitError.check(
                    git_merge(
                        repo,
                        buffer.baseAddress,
                        1,
                        nil,
                        nil
                    )
                )
            }

            var index: OpaquePointer?
            try GitError.check(git_repository_index(&index, repo))
            defer { git_index_free(index) }

            if git_index_has_conflicts(index) == 1 {
                throw GitError(.mergeConflict)
            }

            var treeOID = git_oid()
            try GitError.check(git_index_write_tree(&treeOID, index))
            var tree: OpaquePointer?
            try GitError.check(git_tree_lookup(&tree, repo, &treeOID))
            defer { git_tree_free(tree) }

            var ours: OpaquePointer?
            try GitError.check(git_commit_lookup(&ours, repo, &headOID))
            defer { git_commit_free(ours) }

            var signature: UnsafeMutablePointer<git_signature>?
            try GitError.check(git_signature_default(&signature, repo))
            defer { git_signature_free(signature) }

            let message = "Merge \(refName)"
            var commitOID = git_oid()
            var parents: [OpaquePointer?] = [ours, theirCommit]
            try parents.withUnsafeMutableBufferPointer { buffer in
                try GitError.check(
                    git_commit_create(
                        &commitOID,
                        repo,
                        "HEAD",
                        signature,
                        signature,
                        nil,
                        message,
                        tree,
                        2,
                        buffer.baseAddress
                    )
                )
            }

            git_repository_state_cleanup(repo)
            return .merged(oid: Self.oidString(&commitOID))
        } catch {
            // Abort: reset to pre-merge HEAD and clear merge state.
            git_repository_state_cleanup(repo)
            var commit: OpaquePointer?
            if git_commit_lookup(&commit, repo, &headOID) == 0, let commit {
                defer { git_commit_free(commit) }
                var opts = git_checkout_options()
                _ = git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION))
                opts.checkout_strategy = GIT_CHECKOUT_FORCE.rawValue
                _ = git_reset(repo, commit, GIT_RESET_HARD, &opts)
            }
            if let gitError = error as? GitError, gitError.kind == .mergeConflict {
                throw gitError
            }
            throw GitError(.mergeConflict)
        }
    }

    private func fastForward(to commit: OpaquePointer?) throws -> GitMergeResult {
        guard let commit else { throw GitError(.other("Missing commit for fast-forward")) }
        var headRef: OpaquePointer?
        try GitError.check(git_repository_head(&headRef, repo))
        defer { git_reference_free(headRef) }

        guard let refName = git_reference_name(headRef) else {
            throw GitError(.other("Could not read HEAD ref name"))
        }

        // Checkout first, then move the branch tip (set_target invalidates headRef).
        var opts = git_checkout_options()
        try GitError.check(git_checkout_options_init(&opts, UInt32(GIT_CHECKOUT_OPTIONS_VERSION)))
        opts.checkout_strategy = GIT_CHECKOUT_SAFE.rawValue
        try GitError.check(git_checkout_tree(repo, commit, &opts))

        let targetOID = git_commit_id(commit)
        var newRef: OpaquePointer?
        try GitError.check(git_reference_set_target(&newRef, headRef, targetOID, "fast-forward"))
        defer { git_reference_free(newRef) }
        try GitError.check(git_repository_set_head(repo, refName))

        var oid = targetOID!.pointee
        return .fastForward(oid: Self.oidString(&oid))
    }

    private static func oidString(_ oid: UnsafePointer<git_oid>) -> String {
        var buf = [UInt8](repeating: 0, count: 41)
        buf.withUnsafeMutableBufferPointer { buffer in
            _ = git_oid_tostr(buffer.baseAddress, 41, oid)
        }
        if let end = buf.firstIndex(of: 0) {
            return String(decoding: buf[..<end], as: UTF8.self)
        }
        return String(decoding: buf, as: UTF8.self)
    }

    private func requireToken() throws -> String {
        guard let token = try patStore.load(), !token.isEmpty else {
            throw GitError(.missingCredentials)
        }
        return token
    }
}
