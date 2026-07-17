import XCTest
@testable import RotoskopWorkspace

final class InMemoryFileSystemTests: XCTestCase {

    func testWriteReadRoundTrip() throws {
        let fs = InMemoryFileSystem()
        let path = WorkspacePath("src/main.s")
        try fs.writeText(path, "LDA #$01\n")
        XCTAssertTrue(fs.exists(path))
        XCTAssertEqual(try fs.readText(path), "LDA #$01\n")
    }

    func testWriteCreatesIntermediateDirectories() throws {
        let fs = InMemoryFileSystem()
        try fs.writeText(WorkspacePath("a/b/c.txt"), "hi")
        XCTAssertTrue(fs.isDirectory(WorkspacePath("a")))
        XCTAssertTrue(fs.isDirectory(WorkspacePath("a/b")))
    }

    func testListReturnsSortedEntries() throws {
        let fs = InMemoryFileSystem()
        try fs.writeText(WorkspacePath("z.txt"), "z")
        try fs.writeText(WorkspacePath("a.txt"), "a")
        try fs.createDirectory(WorkspacePath("dir"))
        let entries = try fs.list(.root)
        XCTAssertEqual(entries.map { $0.name }, ["a.txt", "dir", "z.txt"])
    }

    func testRemoveDirectoryRemovesContents() throws {
        let fs = InMemoryFileSystem()
        try fs.writeText(WorkspacePath("dir/file.txt"), "x")
        try fs.remove(WorkspacePath("dir"))
        XCTAssertFalse(fs.exists(WorkspacePath("dir")))
        XCTAssertFalse(fs.exists(WorkspacePath("dir/file.txt")))
    }

    func testMoveFile() throws {
        let fs = InMemoryFileSystem()
        try fs.writeText(WorkspacePath("old.txt"), "data")
        try fs.move(from: WorkspacePath("old.txt"), to: WorkspacePath("new.txt"))
        XCTAssertFalse(fs.exists(WorkspacePath("old.txt")))
        XCTAssertEqual(try fs.readText(WorkspacePath("new.txt")), "data")
    }

    func testReadMissingFileThrows() {
        let fs = InMemoryFileSystem()
        XCTAssertThrowsError(try fs.readFile(WorkspacePath("nope"))) { error in
            XCTAssertEqual(error as? FileSystemError, .notFound(WorkspacePath("nope")))
        }
    }
}
