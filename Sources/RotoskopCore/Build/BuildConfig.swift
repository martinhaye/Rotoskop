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
        guard let root = try Yams.load(yaml: text) as? [String: Any] else {
            throw BuildError.invalidConfig("root must be a mapping")
        }
        let name = root["name"] as? String ?? "project"
        let includeDirs = (root["include_dirs"] as? [Any])?.compactMap { $0 as? String } ?? []
        let buildDir = root["build_dir"] as? String ?? "build"
        let steps = try parseSteps(root["steps"] as? [Any] ?? [])
        let run = parseRun(root["run"] as? [String: Any] ?? [:])
        var profiles: [String: RunProfile] = [:]
        if let pmap = root["profiles"] as? [String: Any] {
            for (k, v) in pmap {
                if let d = v as? [String: Any] {
                    profiles[k] = parseRun(d, base: run)
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
    case packImage(format: String, out: String, boot: String, root: [String: String], dirs: [String: [String]])
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

private func parseSteps(_ list: [Any]) throws -> [BuildStep] {
    var steps: [BuildStep] = []
    for item in list {
        guard let map = item as? [String: Any], let (key, val) = map.first,
              let body = val as? [String: Any] else {
            throw BuildError.invalidConfig("each step must be a single-key mapping")
        }
        switch key {
        case "generate":
            let lang = body["language"] as? String ?? "js"
            guard let script = body["script"] as? String, let out = body["out"] as? String else {
                throw BuildError.invalidConfig("generate needs script and out")
            }
            steps.append(.generate(language: lang, script: script, out: out))
        case "assemble":
            let sources: [String]
            if let s = body["sources"] as? String {
                sources = [s]
            } else if let arr = body["sources"] as? [Any] {
                sources = arr.compactMap { $0 as? String }
            } else {
                throw BuildError.invalidConfig("assemble needs sources")
            }
            let out = body["out"] as? String
            let outDir = body["out_dir"] as? String
            steps.append(.assemble(sources: sources, out: out, outDir: outDir))
        case "pack_image":
            let format = body["format"] as? String ?? "runix_2mg"
            guard let out = body["out"] as? String, let boot = body["boot"] as? String else {
                throw BuildError.invalidConfig("pack_image needs out and boot")
            }
            var root: [String: String] = [:]
            if let r = body["root"] as? [String: Any] {
                for (k, v) in r { if let s = v as? String { root[k] = s } }
            }
            var dirs: [String: [String]] = [:]
            if let d = body["dirs"] as? [String: Any] {
                for (k, v) in d {
                    if let s = v as? String {
                        dirs[k] = [s]
                    } else if let arr = v as? [Any] {
                        dirs[k] = arr.compactMap { $0 as? String }
                    }
                }
            }
            steps.append(.packImage(format: format, out: out, boot: boot, root: root, dirs: dirs))
        default:
            throw BuildError.invalidConfig("unknown step kind '\(key)'")
        }
    }
    return steps
}

private func parseRun(_ map: [String: Any], base: RunProfile = RunProfile()) -> RunProfile {
    var load: [(String, UInt16)] = base.load
    if let arr = map["load"] as? [Any] {
        load = []
        for item in arr {
            if let m = item as? [String: Any],
               let file = m["file"] as? String,
               let addr = parseAddr(m["addr"]) {
                load.append((file, addr))
            }
        }
    }
    return RunProfile(
        disk: map["disk"] as? String ?? base.disk,
        load: load,
        start: parseAddr(map["start"]) ?? base.start,
        maxInstructions: (map["max_instructions"] as? Int) ?? base.maxInstructions,
        keys: (map["keys"] as? [Any])?.compactMap { $0 as? String } ?? base.keys,
        trace: (map["trace"] as? Bool) ?? base.trace,
        screen: (map["screen"] as? Bool) ?? base.screen
    )
}

private func parseAddr(_ value: Any?) -> UInt16? {
    guard let value else { return nil }
    if let n = value as? Int { return UInt16(truncatingIfNeeded: n) }
    if let n = value as? NSNumber { return UInt16(truncatingIfNeeded: n.intValue) }
    if let s = value as? String {
        var t = s.trimmingCharacters(in: .whitespaces)
        if t.hasPrefix("0x") || t.hasPrefix("0X") { t = String(t.dropFirst(2)) }
        if t.hasPrefix("$") { t = String(t.dropFirst()) }
        return UInt16(t, radix: 16) ?? UInt16(t)
    }
    return nil
}
