import Foundation
import Testing
@testable import RotoskopCore

@Suite("Test specs")
struct TestSpecTests {
    @Test func parseDirectives() throws {
        let text = """
        ; @test keys cd rtest\\ntestbcd1\\nhalt\\n
        ; @test max_instructions 500000
        ; @test stop success
        	print "T1: '123'"
        ; @test expect T1: '123' = 123.
        ; @test expect T2: '-123' = -123.
        """
        let spec = try TestSpecParser.parse(text: text, path: "/proj/src/rtest/testbcd1.s")
        #expect(spec?.name == "testbcd1")
        #expect(spec?.keys == "cd rtest\\ntestbcd1\\nhalt\\n")
        #expect(spec?.maxInstructions == 500_000)
        #expect(spec?.stop == .success)
        #expect(spec?.expects == ["T1: '123' = 123.", "T2: '-123' = -123."])
    }

    @Test func skipFileWithoutDirectives() throws {
        let spec = try TestSpecParser.parse(text: "; just a comment\n lda #1\n", path: "bootstub.s")
        #expect(spec == nil)
    }

    @Test func requireExpectOrStop() {
        #expect(throws: BuildError.self) {
            _ = try TestSpecParser.parse(
                text: "; @test keys halt\\n\n",
                path: "halt.s"
            )
        }
    }

    @Test func stopOnlyIsEnough() throws {
        let spec = try TestSpecParser.parse(
            text: "; @test keys halt\\n\n; @test stop success\n",
            path: "tests/halt.test"
        )
        #expect(spec?.name == "halt")
        #expect(spec?.stop == .success)
        #expect(spec?.expects.isEmpty == true)
    }

    @Test func unknownDirective() {
        #expect(throws: BuildError.self) {
            _ = try TestSpecParser.parse(text: "; @test regex foo\n", path: "x.s")
        }
    }

    @Test func globStemFilter() {
        #expect(SourceGlob.matches("testbcd*", "testbcd1"))
        #expect(SourceGlob.matches("*.s", "testbcd1.s"))
        #expect(SourceGlob.matches("halt", "halt"))
        #expect(!SourceGlob.matches("testbcd*", "testpool"))
    }

    @Test func discoverFromTempDir() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-discover-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tests"), withIntermediateDirectories: true)
        try """
        ; @test keys halt\\n
        ; @test stop success
        """.write(to: root.appendingPathComponent("tests/halt.test"), atomically: true, encoding: .utf8)
        try """
        ; @test max_instructions 10000
        ; @test stop limit
        ; @test expect Welcome
        """.write(to: root.appendingPathComponent("tests/welcome.test"), atomically: true, encoding: .utf8)
        let config = ProjectConfig(tests: TestsConfig(files: ["tests/*.test"]))
        let all = try TestDiscovery.discover(projectRoot: root.path, config: config)
        #expect(all.map(\.name).sorted() == ["halt", "welcome"])
        let one = try TestDiscovery.discover(projectRoot: root.path, config: config, names: ["halt"])
        #expect(one.map(\.name) == ["halt"])
        let glob = try TestDiscovery.discover(projectRoot: root.path, config: config, names: ["w*"])
        #expect(glob.map(\.name) == ["welcome"])
    }
}
