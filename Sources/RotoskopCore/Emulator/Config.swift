import Foundation

public struct BinaryLoad: Equatable, Sendable {
    public var file: String
    public var loadAddress: UInt16

    public init(file: String, loadAddress: UInt16) {
        self.file = file
        self.loadAddress = loadAddress
    }
}

public struct SimulatorConfig: Equatable, Sendable {
    public var binaries: [BinaryLoad]
    public var startAddress: UInt16

    public init(binaries: [BinaryLoad], startAddress: UInt16) {
        self.binaries = binaries
        self.startAddress = startAddress
    }

    public static func fromJSONFile(_ path: String) throws -> SimulatorConfig {
        let url = URL(fileURLWithPath: path)
        let data = try Data(contentsOf: url)
        let root = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            ?? { throw ConfigError.invalid("root must be an object") }()

        guard let startRaw = root["start_addr"] else {
            throw ConfigError.invalid("missing start_addr")
        }
        let start = try parseAddress(startRaw)

        var binaries: [BinaryLoad] = []
        if let list = root["binaries"] as? [[String: Any]] {
            for item in list {
                guard let file = item["file"] as? String else {
                    throw ConfigError.invalid("binary missing file")
                }
                guard let loadRaw = item["load_addr"] else {
                    throw ConfigError.invalid("binary missing load_addr")
                }
                var resolved = file
                if !file.hasPrefix("/") {
                    resolved = url.deletingLastPathComponent().appendingPathComponent(file).path
                }
                binaries.append(BinaryLoad(file: resolved, loadAddress: try parseAddress(loadRaw)))
            }
        }

        return SimulatorConfig(binaries: binaries, startAddress: start)
    }

    private static func parseAddress(_ value: Any) throws -> UInt16 {
        if let n = value as? Int {
            return UInt16(truncatingIfNeeded: n)
        }
        if let n = value as? NSNumber {
            return UInt16(truncatingIfNeeded: n.intValue)
        }
        if let s = value as? String {
            var t = s.trimmingCharacters(in: .whitespaces)
            if t.hasPrefix("0x") || t.hasPrefix("0X") {
                t = String(t.dropFirst(2))
                guard let v = UInt16(t, radix: 16) else { throw ConfigError.invalid("bad address \(s)") }
                return v
            }
            if t.hasPrefix("$") {
                t = String(t.dropFirst())
                guard let v = UInt16(t, radix: 16) else { throw ConfigError.invalid("bad address \(s)") }
                return v
            }
            if let v = UInt16(t) { return v }
            if let v = UInt16(t, radix: 16) { return v }
        }
        throw ConfigError.invalid("bad address \(value)")
    }
}

public enum ConfigError: Error, CustomStringConvertible {
    case invalid(String)

    public var description: String {
        switch self {
        case .invalid(let m): return m
        }
    }
}
