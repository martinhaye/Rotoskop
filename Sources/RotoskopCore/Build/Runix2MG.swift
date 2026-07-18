import Foundation

/// Port of mkrunix.py — ProDOS-order .2mg with Runix directory layout.
public enum Runix2MG {
    public static let blockSize = 512
    public static let imageBlocks = 65535
    public static let blocksPerDir = 4
    public static let rootDirBlock = 1

    public struct Inputs: Sendable {
        public var boot: Data
        public var rootFiles: [(name: String, data: Data)]  // e.g. ("runix", kernel)
        public var directories: [(name: String, files: [(name: String, data: Data)])]

        public init(
            boot: Data,
            rootFiles: [(name: String, data: Data)] = [],
            directories: [(name: String, files: [(name: String, data: Data)])] = []
        ) {
            self.boot = boot
            self.rootFiles = rootFiles
            self.directories = directories
        }
    }

    public static func build(_ inputs: Inputs) -> Data {
        var image = [UInt8](repeating: 0, count: imageBlocks * blockSize)
        var nextFree = 5

        // Boot block 0
        let bootSlice = Array(inputs.boot.prefix(blockSize))
        writeBlock(&image, 0, bootSlice)

        var rootEntries: [Data] = []

        for (name, data) in inputs.rootFiles {
            let start = nextFree
            nextFree = writeFile(&image, start, [UInt8](data))
            rootEntries.append(dirEntry(name: name, startBlock: start, lengthPages: pagesNeeded(data.count)))
        }

        // Reserve subdirectory blocks, then fill
        var dirBlocks: [(name: String, block: Int, files: [(String, Data)])] = []
        for dir in inputs.directories {
            let block = nextFree
            nextFree += blocksPerDir
            rootEntries.append(dirEntry(name: dir.name, startBlock: block, lengthPages: 0xF8))
            dirBlocks.append((dir.name, block, dir.files))
        }

        // Write root directory
        var rootDir = writeDirectoryEntries(rootEntries)
        rootDir[0] = UInt8(nextFree & 0xFF)
        rootDir[1] = UInt8((nextFree >> 8) & 0xFF)
        writeBlock(&image, rootDirBlock, Array(rootDir.prefix(blockSize * blocksPerDir)))

        // Write each subdirectory and its files
        for (_, block, files) in dirBlocks {
            var entries: [Data] = []
            var nf = nextFree
            for (fname, data) in files {
                let start = nf
                nf = writeFile(&image, start, [UInt8](data))
                entries.append(dirEntry(name: fname, startBlock: start, lengthPages: pagesNeeded(data.count)))
            }
            nextFree = nf
            var dirData = writeDirectoryEntries(entries)
            dirData[0] = UInt8(rootDirBlock & 0xFF)
            dirData[1] = UInt8((rootDirBlock >> 8) & 0xFF)
            writeBlock(&image, block, Array(dirData.prefix(blockSize * blocksPerDir)))
        }

        // Patch next-free in root after all files placed
        let rootOff = rootDirBlock * blockSize
        image[rootOff] = UInt8(nextFree & 0xFF)
        image[rootOff + 1] = UInt8((nextFree >> 8) & 0xFF)

        return make2MG(payload: Data(image))
    }

    public static func make2MG(payload: Data) -> Data {
        var hdr = [UInt8](repeating: 0, count: 64)
        hdr.replaceSubrange(0..<4, with: Array("2IMG".utf8))
        hdr.replaceSubrange(4..<8, with: Array("RNIX".utf8))
        put16(&hdr, 0x08, 64)
        put16(&hdr, 0x0A, 1)
        put32(&hdr, 0x0C, 1) // ProDOS order
        put32(&hdr, 0x10, 0)
        put32(&hdr, 0x14, UInt32(imageBlocks))
        put32(&hdr, 0x18, 64)
        put32(&hdr, 0x1C, UInt32(payload.count))
        var out = Data(hdr)
        out.append(payload)
        return out
    }

    // MARK: - Internals

    private static func pagesNeeded(_ len: Int) -> Int { (len + 255) / 256 }
    private static func blocksNeeded(_ len: Int) -> Int { (len + blockSize - 1) / blockSize }

    private static func dirEntry(name: String, startBlock: Int, lengthPages: Int) -> Data {
        var e = Data()
        let nb = Array(name.utf8)
        e.append(UInt8(nb.count))
        e.append(contentsOf: nb)
        e.append(UInt8(startBlock & 0xFF))
        e.append(UInt8((startBlock >> 8) & 0xFF))
        e.append(UInt8(lengthPages & 0xFF))
        return e
    }

    private static func writeDirectoryEntries(_ entries: [Data]) -> [UInt8] {
        var dir = [UInt8](repeating: 0, count: blocksPerDir * blockSize)
        var offset = 2
        for entry in entries {
            let entryLen = entry.count
            let currentBlockOffset = offset % blockSize
            let remaining = blockSize - currentBlockOffset
            if entryLen >= remaining {
                offset = ((offset / blockSize) + 1) * blockSize
            }
            for (i, b) in entry.enumerated() {
                dir[offset + i] = b
            }
            offset += entryLen
        }
        return dir
    }

    private static func writeBlock(_ image: inout [UInt8], _ block: Int, _ data: [UInt8]) {
        let off = block * blockSize
        for i in 0..<data.count {
            if off + i < image.count {
                image[off + i] = data[i]
            }
        }
    }

    private static func writeFile(_ image: inout [UInt8], _ startBlock: Int, _ data: [UInt8]) -> Int {
        let off = startBlock * blockSize
        for i in 0..<data.count {
            if off + i < image.count { image[off + i] = data[i] }
        }
        return startBlock + blocksNeeded(data.count)
    }

    private static func put16(_ buf: inout [UInt8], _ off: Int, _ v: UInt16) {
        buf[off] = UInt8(v & 0xFF)
        buf[off + 1] = UInt8((v >> 8) & 0xFF)
    }

    private static func put32(_ buf: inout [UInt8], _ off: Int, _ v: UInt32) {
        buf[off] = UInt8(v & 0xFF)
        buf[off + 1] = UInt8((v >> 8) & 0xFF)
        buf[off + 2] = UInt8((v >> 16) & 0xFF)
        buf[off + 3] = UInt8((v >> 24) & 0xFF)
    }
}
