import Foundation
import Testing
@testable import RotoskopCore

@Suite("Build system")
struct BuildTests {
    @Test func parseYaml() throws {
        let yaml = """
        name: demo
        include_dirs: [src/include]
        build_dir: build
        steps:
          - assemble:
              sources: src/boot/boot.s
              out: boot.bin
          - pack_image:
              format: runix_2mg
              out: out.2mg
              boot: boot.bin
              root:
                runix: kernel.bin
              dirs:
                runes: [runes/*.bin]
                bin: [bin/*.bin]
                demos: [demos/*.bin]
                rtest: [rtest/*.bin]
        run:
          disk: build/out.2mg
          load:
            - { file: build/bootstub.bin, addr: 0x1000 }
          start: 0x1000
          max_instructions: 100000
        profiles:
          halt:
            keys: ["halt\\n"]
        """
        let cfg = try ProjectConfig.parse(yaml: yaml)
        #expect(cfg.name == "demo")
        #expect(cfg.steps.count == 2)
        #expect(cfg.run.start == 0x1000)
        #expect(cfg.run.load.count == 1)
        #expect(cfg.run.load[0].file == "build/bootstub.bin")
        #expect(cfg.run.load[0].addr == 0x1000)
        if case .packImage(_, _, _, _, let dirs) = cfg.steps[1] {
            #expect(dirs.map(\.0) == ["runes", "bin", "demos", "rtest"])
        } else {
            Issue.record("expected pack_image step")
        }
        let halt = try cfg.resolvedRun(profile: "halt")
        #expect(halt.keys == ["halt\n"])
        #expect(halt.disk == "build/out.2mg")
        #expect(throws: BuildError.self) {
            _ = try cfg.resolvedRun(profile: "missing")
        }
        let session = try RunSession.from(projectRoot: "/proj", config: cfg, profile: "halt")
        #expect(session.disk == "/proj/build/out.2mg")
        #expect(session.load.first?.file == "/proj/build/bootstub.bin")
        #expect(session.keys == ["halt\n"])
        #expect(session.maxInstructions == 100_000)
    }

    @Test func packImageHeader() {
        let boot = Data([0x01, 0x52, 0x75]) + Data(count: 100)
        let image = Runix2MG.build(.init(
            boot: boot,
            rootFiles: [("runix", Data([0x4C, 0xF9, 0xFF]))],
            directories: [("bin", [("halt", Data([0x4C, 0xF9, 0xFF]))])]
        ))
        #expect(Array(image.prefix(4)) == Array("2IMG".utf8))
        #expect(Array(image[4..<8]) == Array("RNIX".utf8))
        #expect(image.count == 64 + Runix2MG.imageBlocks * Runix2MG.blockSize)
        // Boot payload after header
        #expect(image[64] == 0x01)
        #expect(image[65] == 0x52)
    }

    @Test func miniProjectBuild() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // BuildTests.swift dir... actually in Assembler or root Tests
            .deletingLastPathComponent() // RotoskopCoreTests
            .appendingPathComponent("Fixtures/MiniProject")
            .path
        // #filePath is Tests/RotoskopCoreTests/BuildTests.swift or nested
        let fixture = findFixture()
        let engine = try BuildEngine(projectRoot: fixture)
        let result = engine.build()
        #expect(result.succeeded, "\(result.diagnostics)")
        let bin = (fixture as NSString).appendingPathComponent("build/main.bin")
        #expect(FileManager.default.fileExists(atPath: bin))
        let data = try Data(contentsOf: URL(fileURLWithPath: bin))
        // ldx #5 ('hello'.count) ; jmp $FFF9  OR ldx msg / msg is .byt 5,"hello"
        // main: ldx msg (abs) = AE lo hi, then jmp = 4C F9 FF — msg at some addr
        #expect(data.count >= 3)
        #expect(data[data.count - 3] == 0x4C)
        #expect(data[data.count - 2] == 0xF9)
        #expect(data[data.count - 1] == 0xFF)
        let img = (fixture as NSString).appendingPathComponent("build/mini.2mg")
        #expect(FileManager.default.fileExists(atPath: img))
        _ = root
    }

    @Test func assembleFailureKeepsStructuredDiagnostics() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-bad-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let src = root.appendingPathComponent("bad.s")
        try ".include \"does-not-exist.i\"\n".write(to: src, atomically: true, encoding: .utf8)
        let yaml = """
        name: bad
        build_dir: build
        steps:
          - assemble:
              sources: bad.s
              out: bad.bin
        """
        try yaml.write(to: root.appendingPathComponent("rotoskop.yaml"), atomically: true, encoding: .utf8)

        let engine = try BuildEngine(projectRoot: root.path)
        let result = engine.build()
        #expect(!result.succeeded)
        #expect(!result.diagnostics.isEmpty)
        #expect(result.diagnostics.contains { $0.location != nil })
    }

    @Test func dirtinessStamp() throws {
        let fixture = findFixture()
        let config = try ProjectConfig.load(fromProjectRoot: fixture)
        let engine = try BuildEngine(projectRoot: fixture)
        let result = engine.build()
        #expect(result.succeeded)
        #expect(!BuildDirtiness.isDirty(projectRoot: fixture, config: config))

        let main = (fixture as NSString).appendingPathComponent("src/main.s")
        let now = Date().addingTimeInterval(2)
        try FileManager.default.setAttributes([.modificationDate: now], ofItemAtPath: main)
        #expect(BuildDirtiness.isDirty(projectRoot: fixture, config: config))
    }

    private func findFixture() -> String {
        // Walk up from this source file
        var url = URL(fileURLWithPath: #filePath)
        for _ in 0..<5 {
            let candidate = url.appendingPathComponent("Fixtures/MiniProject")
            if FileManager.default.fileExists(atPath: candidate.appendingPathComponent("rotoskop.yaml").path) {
                return candidate.path
            }
            let alt = url.deletingLastPathComponent().appendingPathComponent("Fixtures/MiniProject")
            if FileManager.default.fileExists(atPath: alt.appendingPathComponent("rotoskop.yaml").path) {
                return alt.path
            }
            url = url.deletingLastPathComponent()
        }
        return "Tests/Fixtures/MiniProject"
    }
}
