import Foundation
import Testing
@testable import RotoskopCore

@Suite("Test runner")
struct TestRunnerTests {
    @Test func screenExpectAndStopSuccess() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-trun-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("src"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("tests"), withIntermediateDirectories: true)

        try """
        .org $1000
        	ldx #0
        loop:
        	lda msg,x
        	beq done
        	ora #$80
        	sta $400,x
        	inx
        	bne loop
        done:
        	jmp $FFF9
        msg:	.byte "HelloTest", 0
        """.write(to: root.appendingPathComponent("src/main.s"), atomically: true, encoding: .utf8)

        try """
        name: tproj
        build_dir: build
        steps:
          - assemble:
              sources: src/main.s
              out: main.bin
        run:
          load:
            - { file: build/main.bin, addr: 0x1000 }
          start: 0x1000
          max_instructions: 1000
        tests:
          files: tests/*.test
        """.write(to: root.appendingPathComponent("rotoskop.yaml"), atomically: true, encoding: .utf8)

        try """
        ; @test stop success
        ; @test expect HelloTest
        """.write(to: root.appendingPathComponent("tests/hello.test"), atomically: true, encoding: .utf8)

        let engine = try BuildEngine(projectRoot: root.path)
        let built = engine.build()
        #expect(built.succeeded, "\(built.diagnostics)")

        let config = try ProjectConfig.load(fromProjectRoot: root.path)
        let summary = try TestRunner.run(projectRoot: root.path, config: config)
        #expect(summary.succeeded)
        #expect(summary.results.first?.screen.contains("HelloTest") == true)

        try """
        ; @test stop success
        ; @test expect MissingText
        """.write(to: root.appendingPathComponent("tests/hello.test"), atomically: true, encoding: .utf8)
        let failed = try TestRunner.run(projectRoot: root.path, config: config)
        #expect(!failed.succeeded)
        #expect(failed.results.first?.missingExpects == ["MissingText"])
    }
}
