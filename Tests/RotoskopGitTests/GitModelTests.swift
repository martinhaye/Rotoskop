import XCTest
@testable import RotoskopGit

final class GitModelTests: XCTestCase {

    func testSyncStatusCleanliness() {
        XCTAssertTrue(SyncStatus(currentBranch: "main").isClean)
        XCTAssertFalse(SyncStatus(currentBranch: "main", hasLocalChanges: true).isClean)
        XCTAssertFalse(SyncStatus(currentBranch: "main", ahead: 1).isClean)
        XCTAssertFalse(SyncStatus(currentBranch: "main", behind: 2).isClean)
    }

    func testRepositoryDefaults() {
        let repo = Repository(id: "1",
                              displayName: "Rotoskop",
                              remoteURL: "https://example.com/r.git",
                              localSlug: "rotoskop")
        XCTAssertEqual(repo.defaultBranch, "main")
    }

    // A tiny fake demonstrating the GitService seam is usable without any real
    // git implementation — this is how the app's view models will be tested.
    final class FakeGitService: GitService {
        private(set) var pushed = false
        func clone(_ repository: Repository, credentials: GitCredentials?) async throws {}
        func status(_ repository: Repository) async throws -> SyncStatus {
            SyncStatus(currentBranch: repository.defaultBranch)
        }
        func pull(_ repository: Repository, credentials: GitCredentials?) async throws -> SyncStatus {
            SyncStatus(currentBranch: repository.defaultBranch)
        }
        func push(_ repository: Repository, credentials: GitCredentials?) async throws -> SyncStatus {
            pushed = true
            return SyncStatus(currentBranch: repository.defaultBranch)
        }
        func commitAll(_ repository: Repository, message: String) async throws {}
    }

    func testFakeGitServicePush() async throws {
        let service = FakeGitService()
        let repo = Repository(id: "1", displayName: "R", remoteURL: "x", localSlug: "r")
        _ = try await service.push(repo, credentials: nil)
        XCTAssertTrue(service.pushed)
    }
}
