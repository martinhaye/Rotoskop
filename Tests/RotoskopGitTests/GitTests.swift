import Foundation
import Testing
@testable import RotoskopGit

@Suite("Git URL")
struct GitURLTests {
    @Test func normalizesOwnerRepoShorthand() throws {
        let url = try GitURL.normalizeHTTPS("octocat/Hello-World")
        #expect(url.absoluteString == "https://github.com/octocat/Hello-World")
    }

    @Test func rejectsSSH() {
        #expect(throws: GitError.self) {
            _ = try GitURL.normalizeHTTPS("git@github.com:octocat/Hello-World.git")
        }
    }

    @Test func suggestedDirectoryName() throws {
        let url = try GitURL.normalizeHTTPS("https://github.com/octocat/Hello-World.git")
        #expect(GitURL.suggestedDirectoryName(from: url) == "Hello-World")
    }
}

@Suite("Local Git ops")
struct LocalGitOpsTests {
    @Test func statusCommitBranchAndCleanMerge() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-git-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoAURL = root.appendingPathComponent("repoA", isDirectory: true)
        try FileManager.default.createDirectory(at: repoAURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoAURL)
        try runGit(["config", "user.name", "Test"], in: repoAURL)
        try runGit(["config", "user.email", "test@example.com"], in: repoAURL)
        try "hello\n".write(to: repoAURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoAURL)
        try runGit(["commit", "-m", "initial"], in: repoAURL)

        let pat = InMemoryPATStore(token: "unused-for-local")
        let repo = try GitRepository(opening: repoAURL, patStore: pat)

        var status = try repo.status()
        #expect(status.isClean)
        #expect(status.branch == "main")

        try "changed\n".write(to: repoAURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try "new\n".write(to: repoAURL.appendingPathComponent("new.txt"), atomically: true, encoding: .utf8)
        status = try repo.status()
        #expect(status.files.count >= 2)

        let commit = try repo.commitAll(
            message: "update",
            authorName: "Test",
            authorEmail: "test@example.com"
        )
        #expect(commit.oid.count == 40)
        #expect(try repo.status().isClean)

        try repo.createBranch("feature", checkout: true)
        #expect(try repo.currentBranchName() == "feature")
        try "feature\n".write(to: repoAURL.appendingPathComponent("feature.txt"), atomically: true, encoding: .utf8)
        _ = try repo.commitAll(message: "feature work", authorName: "Test", authorEmail: "test@example.com")

        try repo.switchBranch("main")
        #expect(try repo.currentBranchName() == "main")

        let merge = try repo.mergeClean(from: "feature")
        if case .fastForward = merge {
            // ok
        } else if case .merged = merge {
            // also ok
        } else {
            Issue.record("Expected FF or merge, got \(merge)")
        }
        #expect(FileManager.default.fileExists(atPath: repoAURL.appendingPathComponent("feature.txt").path))
    }

    @Test func listsRemoteTrackingBranchesAndChecksThemOut() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-remote-branch-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoURL = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Test"], in: repoURL)
        try runGit(["config", "user.email", "test@example.com"], in: repoURL)
        try "main\n".write(to: repoURL.appendingPathComponent("README.md"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "main"], in: repoURL)

        try runGit(["checkout", "-b", "rotoskop"], in: repoURL)
        try "roto\n".write(to: repoURL.appendingPathComponent("roto.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "rotoskop"], in: repoURL)
        let rotoskopOID = try runGitOutput(["rev-parse", "HEAD"], in: repoURL).trimmingCharacters(in: .whitespacesAndNewlines)

        // Leave only local main, but keep rotoskop as a remote-tracking ref (post-clone shape).
        try runGit(["checkout", "main"], in: repoURL)
        try runGit(["branch", "-D", "rotoskop"], in: repoURL)
        try runGit(["update-ref", "refs/remotes/origin/rotoskop", rotoskopOID], in: repoURL)

        let repo = try GitRepository(opening: repoURL, patStore: InMemoryPATStore())
        let branches = try repo.listBranches()
        #expect(branches == ["main", "rotoskop"])
        #expect(try repo.currentBranchName() == "main")

        try repo.switchBranch("rotoskop")
        #expect(try repo.currentBranchName() == "rotoskop")
        #expect(FileManager.default.fileExists(atPath: repoURL.appendingPathComponent("roto.txt").path))
        #expect(try repo.listBranches() == ["main", "rotoskop"])
    }

    @Test func mergeConflictAbortsAndLeavesRepoClean() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-merge-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let repoURL = root.appendingPathComponent("repo", isDirectory: true)
        try FileManager.default.createDirectory(at: repoURL, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: repoURL)
        try runGit(["config", "user.name", "Test"], in: repoURL)
        try runGit(["config", "user.email", "test@example.com"], in: repoURL)
        try "base\n".write(to: repoURL.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: repoURL)
        try runGit(["commit", "-m", "base"], in: repoURL)

        try runGit(["checkout", "-b", "other"], in: repoURL)
        try "other\n".write(to: repoURL.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "other"], in: repoURL)

        try runGit(["checkout", "main"], in: repoURL)
        try "main\n".write(to: repoURL.appendingPathComponent("file.txt"), atomically: true, encoding: .utf8)
        try runGit(["commit", "-am", "main"], in: repoURL)

        let before = try String(contentsOf: repoURL.appendingPathComponent("file.txt"), encoding: .utf8)
        let repo = try GitRepository(opening: repoURL, patStore: InMemoryPATStore())

        do {
            _ = try repo.mergeClean(from: "other")
            Issue.record("Expected merge conflict")
        } catch let error as GitError {
            #expect(error.kind == .mergeConflict)
        }

        let after = try String(contentsOf: repoURL.appendingPathComponent("file.txt"), encoding: .utf8)
        #expect(after == before)
        #expect(try repo.status().isClean || !(try repo.status().files.contains { $0.kind == .conflicted }))
        // Merge state should be cleared.
        let gitDir = repoURL.appendingPathComponent(".git")
        #expect(!FileManager.default.fileExists(atPath: gitDir.appendingPathComponent("MERGE_HEAD").path))
    }
}

@Suite("Project store")
struct ProjectStoreTests {
    @Test func addLocalProjectViaFilesystemAndRemove() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-store-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let pat = InMemoryPATStore(token: "test-token")
        let store = try ProjectStore(rootURL: root, patStore: pat)
        #expect(store.projects().isEmpty)

        // Seed a fake clone directory + manifest entry without network.
        let clones = root.appendingPathComponent("Clones", isDirectory: true)
        let projectDir = clones.appendingPathComponent("demo", isDirectory: true)
        try FileManager.default.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try runGit(["init", "-b", "main"], in: projectDir)
        try runGit(["config", "user.name", "Test"], in: projectDir)
        try runGit(["config", "user.email", "test@example.com"], in: projectDir)
        try "x\n".write(to: projectDir.appendingPathComponent("a.txt"), atomically: true, encoding: .utf8)
        try runGit(["add", "."], in: projectDir)
        try runGit(["commit", "-m", "init"], in: projectDir)

        let record = ProjectRecord(
            name: "demo",
            remoteURL: "https://github.com/example/demo.git",
            directoryName: "demo"
        )
        // Write manifest directly then reload store.
        let encoder = JSONEncoder()
        try encoder.encode([record]).write(to: root.appendingPathComponent("projects.json"))

        let reloaded = try ProjectStore(rootURL: root, patStore: pat)
        #expect(reloaded.projects().count == 1)
        let opened = try reloaded.openRepository(for: reloaded.projects()[0])
        #expect(try opened.currentBranchName() == "main")

        try reloaded.remove(reloaded.projects()[0])
        #expect(reloaded.projects().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: projectDir.path))
    }
}

@Suite("PAT store")
struct PATStoreTests {
    @Test func inMemoryRoundTrip() throws {
        let store = InMemoryPATStore()
        #expect(try store.load() == nil)
        try store.save("ghp_test")
        #expect(try store.load() == "ghp_test")
        try store.clear()
        #expect(try store.load() == nil)
    }
}

private func runGit(_ args: [String], in directory: URL) throws {
    _ = try runGitOutput(args, in: directory)
}

private func runGitOutput(_ args: [String], in directory: URL) throws -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
    process.arguments = args
    process.currentDirectoryURL = directory
    let err = Pipe()
    let out = Pipe()
    process.standardError = err
    process.standardOutput = out
    try process.run()
    process.waitUntilExit()
    guard process.terminationStatus == 0 else {
        let message = String(data: err.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        throw GitError(.other("git \(args.joined(separator: " ")) failed: \(message)"))
    }
    return String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
}
