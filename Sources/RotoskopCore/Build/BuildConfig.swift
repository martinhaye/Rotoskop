import Foundation
import Yams

public struct ProjectConfig: Sendable {
    public var name: String
    public var includeDirs: [String]
    public var buildDir: String
    public var steps: [BuildStep]
    public var run: RunProfile
    public var profiles: [String: RunProfile]

    public init(
        name: String = "project",
        includeDirs: [String] = [],
        buildDir: String = "build",
        steps: [BuildStep] = [],
        run: RunProfile = RunProfile(),
        profiles: [String: RunProfile] = [:]
    ) {
        self.name = name
        self.includeDirs = includeDirs
        self.buildDir = buildDir
        self.steps = steps
        self.run = run
        self.profiles = profiles
    }

    public static func load(fromProjectRoot root: String) throws -> ProjectConfig {
        let path = (root as NSString).appendingPathComponent("rotoskop.yaml")
        return try load(fromFile: path)
    }

    public static func load(fromFile path: String) throws -> ProjectConfig {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(yaml: text)
    }

    public static func parse(yaml text: String) throws -> ProjectConfig {
        guard let rootNode = try Yams.compose(yaml: text) else {
            throw BuildError.invalidConfig("empty yaml")
        }
        guard let root = rootNode.mapping else {
            throw BuildError.invalidConfig("root must be a mapping")
        }
        let name = root["name"]?.string ?? "project"
        let includeDirs = root["include_dirs"]?.sequence?.compactMap(\.string) ?? []
        let buildDir = root["build_dir"]?.string ?? "build"
        let steps = try parseSteps(root["steps"]?.sequence ?? [])
        let run = parseRunNode(root["run"])
        var profiles: [String: RunProfile] = [:]
        if let pmap = root["profiles"]?.mapping {
            for (k, v) in pmap {
                if let key = k.string {
                    profiles[key] = parseRunNode(v, base: run)
                }
            }
        }
        return ProjectConfig(
            name: name,
            includeDirs: includeDirs,
            buildDir: buildDir,
            steps: steps,
            run: run,
            profiles: profiles
        )
    }

    public func resolvedRun(profile: String?) -> RunProfile {
        guard let profile, let overlay = profiles[profile] else { return run }
        return run.merging(overlay)
    }
}

public enum BuildStep: Sendable {
    case generate(language: String, script: String, out: String)
    case assemble(sources: [String], out: String?, outDir: String?)
    case packImage(format: String, out: String, boot: String, root: [(String, String)], dirs: [(String, [String])])
}

public struct RunProfile: Sendable {
    public var disk: String?
    public var load: [(file: String, addr: UInt16)]
    public var start: UInt16?
    public var maxInstructions: Int?
    public var keys: [String]
    public var trace: Bool
    public var screen: Bool

    public init(
        disk: String? = nil,
        load: [(file: String, addr: UInt16)] = [],
        start: UInt16? = nil,
        maxInstructions: Int? = nil,
        keys: [String] = [],
        trace: Bool = false,
        screen: Bool = false
    ) {
        self.disk = disk
        self.load = load
        self.start = start
        self.maxInstructions = maxInstructions
        self.keys = keys
        self.trace = trace
        self.screen = screen
    }

    func merging(_ overlay: RunProfile) -> RunProfile {
        RunProfile(
            disk: overlay.disk ?? disk,
            load: overlay.load.isEmpty ? load : overlay.load,
            start: overlay.start ?? start,
            maxInstructions: overlay.maxInstructions ?? maxInstructions,
            keys: overlay.keys.isEmpty ? keys : overlay.keys,
            trace: overlay.trace || trace,
            screen: overlay.screen || screen
        )
    }
}

public enum BuildError: Error, CustomStringConvertible {
    case invalidConfig(String)
    case stepFailed(String)
    case io(String)

    public var description: String {
        switch self {
        case .invalidConfig(let m), .stepFailed(let m), .io(let m): return m
        }
    }
}

private func parseSteps(_ list: Yams.Node.Sequence) throws -> [BuildStep] {
    var steps: [BuildStep] = []
    for item in list {
        guard let map = item.mapping, map.count == 1, let (keyNode, bodyNode) = map.first,
              let key = keyNode.string, let body = bodyNode.mapping else {
            throw BuildError.invalidConfig("each step must be a single-key mapping")
        }
        switch key {
        case "generate":
            let lang = body["language"]?.string ?? "js"
            guard let script = body["script"]?.string, let out = body["out"]?.string else {
                throw BuildError.invalidConfig("generate needs script and out")
            }
            steps.append(.generate(language: lang, script: script, out: out))
        case "assemble":
            let sources: [String]
            if let s = body["sources"]?.string {
                sources = [s]
            } else if let arr = body["sources"]?.sequence {
                sources = arr.compactMap(\.string)
            } else {
                throw BuildError.invalidConfig("assemble needs sources")
            }
            let out = body["out"]?.string
            let outDir = body["out_dir"]?.string
            steps.append(.assemble(sources: sources, out: out, outDir: outDir))
        case "pack_image":
            let format = body["format"]?.string ?? "runix_2mg"
            guard let out = body["out"]?.string, let boot = body["boot"]?.string else {
                throw BuildError.invalidConfig("pack_image needs out and boot")
            }
            // Preserve YAML key order (mkrunix: runes, bin, demos, rtest).
            let root = orderedStringMap(body["root"]?.mapping)
            let dirs = orderedStringListMap(body["dirs"]?.mapping)
            steps.append(.packImage(format: format, out: out, boot: boot, root: root, dirs: dirs))
        default:
            throw BuildError.invalidConfig("unknown step kind '\(key)'")
        }
    }
    return steps
}

private func orderedStringMap(_ mapping: Yams.Node.Mapping?) -> [(String, String)] {
    guard let mapping else { return [] }
    var result: [(String, String)] = []
    for (k, v) in mapping {
        if let key = k.string, let val = v.string {
            result.append((key, val))
        }
    }
    return result
}

private func orderedStringListMap(_ mapping: Yams.Node.Mapping?) -> [(String, [String])] {
    guard let mapping else { return [] }
    var result: [(String, [String])] = []
    for (k, v) in mapping {
        guard let key = k.string else { continue }
        if let s = v.string {
            result.append((key, [s]))
        } else if let arr = v.sequence {
            result.append((key, arr.compactMap(\.string)))
        }
    }
    return result
}

private func parseRunNode(_ node: Yams.Node?, base: RunProfile = RunProfile()) -> RunProfile {
    guard let map = node?.mapping else { return base }
    var load: [(String, UInt16)] = base.load
    if let arr = map["load"]?.sequence {
        load = []
        for item in arr {
            if let m = item.mapping,
               let file = m["file"]?.string,
               let addr = parseAddrNode(m["addr"]) {
                load.append((file, addr))
            }
        }
    }
    let keys = map["keys"]?.sequence?.compactMap(\.string) ?? base.keys
    return RunProfile(
        disk: map["disk"]?.string ?? base.disk,
        load: load,
        start: parseAddrNode(map["start"]) ?? base.start,
        maxInstructions: map["max_instructions"]?.int ?? base.maxInstructions,
        keys: keys,
        trace: map["trace"]?.bool ?? base.trace,
        screen: map["screen"]?.bool ?? base.screen
    )
}

private func parseAddrNode(_ node: Yams.Node?) -> UInt16? {
    guard let node else { return nil }
    if let n = node.int { return UInt16(truncatingIfNeeded: n) }
    if let s = node.string {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("0x") || t.hasPrefix("0X") { t = String(t.dropFirst(2)) }
        if t.hasPrefix("$") { t = String(t.dropFirst()) }
        return UInt16(t, radix: 16) ?? UInt16(t)
    }
    return nil
}
