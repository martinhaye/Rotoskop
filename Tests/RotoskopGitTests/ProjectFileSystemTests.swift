import Foundation
import Testing
@testable import RotoskopGit

@Suite("Project file system")
struct ProjectFileSystemTests {
    @Test func listsTreeHidesGitShowsBuild() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        try mkdir(root, "src")
        try write(root, "src/main.s", "lda #0\n")
        try mkdir(root, "build")
        try write(root, "build/out.bin", "x")
        try mkdir(root, ".git")
        try write(root, ".git/config", "hidden")
        try write(root, "README.md", "hi\n")

        let tree = try ProjectFileSystem.listTree(rootURL: root)
        let names = Set(tree.map(\.name))
        #expect(names.contains("src"))
        #expect(names.contains("build"))
        #expect(names.contains("README.md"))
        #expect(!names.contains(".git"))

        let build = try #require(tree.first { $0.name == "build" })
        #expect(build.isDirectory)
        #expect(build.children.map(\.name) == ["out.bin"])
    }

    @Test func createRenameMoveDelete() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let file = try ProjectFileSystem.createFile(
            named: "a.s",
            inDirectory: "",
            rootURL: root,
            contents: "nop\n"
        )
        #expect(file == "a.s")
        #expect(try ProjectFileSystem.readText(rootURL: root, relativePath: "a.s") == "nop\n")

        _ = try ProjectFileSystem.createDirectory(named: "src", inDirectory: "", rootURL: root)
        try ProjectFileSystem.move(from: "a.s", to: "src/a.s", rootURL: root)
        #expect(try ProjectFileSystem.readText(rootURL: root, relativePath: "src/a.s") == "nop\n")

        try ProjectFileSystem.move(from: "src/a.s", to: "src/b.s", rootURL: root)
        try ProjectFileSystem.writeText("lda #1\n", rootURL: root, relativePath: "src/b.s")
        #expect(try ProjectFileSystem.readText(rootURL: root, relativePath: "src/b.s") == "lda #1\n")

        try ProjectFileSystem.delete(relativePath: "src/b.s", rootURL: root)
        #expect(throws: ProjectFileSystem.Error.self) {
            _ = try ProjectFileSystem.readText(rootURL: root, relativePath: "src/b.s")
        }
    }

    @Test func rejectsPathEscapeAndGit() throws {
        let root = try makeRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(throws: ProjectFileSystem.Error.self) {
            _ = try ProjectFileSystem.createFile(named: "../x", inDirectory: "", rootURL: root)
        }
        #expect(throws: ProjectFileSystem.Error.self) {
            try ProjectFileSystem.writeText("x", rootURL: root, relativePath: ".git/config")
        }
        #expect(throws: ProjectFileSystem.Error.self) {
            try ProjectFileSystem.writeText("x", rootURL: root, relativePath: "src/../../etc/passwd")
        }
        #expect(ProjectFileSystem.isAssemblyFile("src/boot.s"))
        #expect(ProjectFileSystem.isAssemblyFile("include/base.i"))
        #expect(!ProjectFileSystem.isAssemblyFile("rotoskop.yaml"))
    }

    private func makeRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-fs-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func mkdir(_ root: URL, _ relative: String) throws {
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent(relative, isDirectory: true),
            withIntermediateDirectories: true
        )
    }

    private func write(_ root: URL, _ relative: String, _ text: String) throws {
        let url = root.appendingPathComponent(relative)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try text.write(to: url, atomically: true, encoding: .utf8)
    }
}
