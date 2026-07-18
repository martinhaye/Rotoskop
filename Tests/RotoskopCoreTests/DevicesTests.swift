import Foundation
import Testing
@testable import RotoskopCore

@Suite("Text screen")
struct TextScreenTests {
    @Test func lineAddresses() {
        #expect(TextScreen.lineAddress(0) == 0x400)
        #expect(TextScreen.lineAddress(1) == 0x480)
        #expect(TextScreen.lineAddress(8) == 0x428)
        #expect(TextScreen.lineAddress(16) == 0x450)
        #expect(TextScreen.lineAddress(23) == 0x7D0)
    }

    @Test func dumpSimpleText() {
        let mem = Memory()
        for addr in 0x400..<0x800 {
            mem.write(UInt16(addr), UInt8(ascii: " "))
        }
        let base = TextScreen.lineAddress(0)
        for (i, ch) in "HELLO".utf8.enumerated() {
            mem.write(base &+ UInt16(i), ch | 0x80)
        }
        #expect(TextScreen.dump(mem) == "HELLO")
    }

    @Test func trimBlankLinesAndWhitespace() {
        let mem = Memory()
        for addr in 0x400..<0x800 {
            mem.write(UInt16(addr), UInt8(ascii: " "))
        }
        let base = TextScreen.lineAddress(5)
        for (i, ch) in "MIDDLE".utf8.enumerated() {
            mem.write(base &+ UInt16(i), ch | 0x80)
        }
        #expect(TextScreen.dump(mem) == "MIDDLE")
    }

    @Test func nonprintableAndFFAsSpace() {
        let mem = Memory()
        // already $FF
        let base = TextScreen.lineAddress(0)
        mem.write(base, UInt8(ascii: "A") | 0x80)
        mem.write(base &+ 1, 0x01)
        mem.write(base &+ 2, UInt8(ascii: "B") | 0x80)
        #expect(TextScreen.dump(mem) == "A B")
    }
}

@Suite("Keyboard")
struct KeyboardTests {
    @Test func simpleInput() {
        let kbd = Keyboard(inputStrings: ["ABC"])
        #expect(kbd.readKbd() == UInt8(ascii: "A") | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == UInt8(ascii: "B") | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == UInt8(ascii: "C") | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == 0x00)
    }

    @Test func newlineToCR() {
        let kbd = Keyboard(inputStrings: ["A\\nB"])
        #expect(kbd.readKbd() == UInt8(ascii: "A") | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == 0x0D | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == UInt8(ascii: "B") | 0x80)
    }

    @Test func hexAndEscape() {
        let kbd = Keyboard(inputStrings: ["\\x1B", "\\e"])
        #expect(kbd.readKbd() == 0x1B | 0x80)
        kbd.clearStrobe()
        #expect(kbd.readKbd() == 0x1B | 0x80)
    }
}

@Suite("Hard drive")
struct HardDriveTests {
    @Test func privateCopyDoesNotMutateOriginal() throws {
        // Minimal .2mg: 64-byte header + one 512-byte block
        var original = Data(count: HardDrive.headerSize + HardDrive.blockSize)
        original[HardDrive.headerSize] = 0xAA

        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent("rotoskop-disk-\(UUID().uuidString).2mg")
        try original.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let hd = try HardDrive(imagePath: tmp.path)
        var block = try hd.readBlock(0)
        #expect(block[0] == 0xAA)
        block[0] = 0x55
        try hd.writeBlock(0, data: block)

        // Original file on disk unchanged
        let reread = try Data(contentsOf: tmp)
        #expect(reread[HardDrive.headerSize] == 0xAA)
        #expect(try hd.readBlock(0)[0] == 0x55)
    }

    @Test func romSignatures() {
        let hd = HardDrive(imageData: Data(count: HardDrive.headerSize + HardDrive.blockSize))
        let rom = hd.romBytes()
        #expect(rom[0x01] == 0x20)
        #expect(rom[0x03] == 0x00)
        #expect(rom[0x05] == 0x03)
        #expect(rom[0xFF] == 0x0A)
        #expect(rom[0x0A] == 0x60)
    }
}
