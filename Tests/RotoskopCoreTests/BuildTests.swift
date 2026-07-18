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
          start: 0x1000
        """
        let cfg = try ProjectConfig.parse(yaml: yaml)
        #expect(cfg.name == "demo")
        #expect(cfg.steps.count == 2)
        #expect(cfg.run.start == 0x1000)
        if case .packImage(_, _, _, _, let dirs) = cfg.steps[1] {
            #expect(dirs.map(\.0) == ["runes", "bin", "demos", "rtest"])
        } else {
            Issue.record("expected pack_image step")
        }
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
