import Foundation

/// Resolved run settings ready to drive `Simulator` (from yaml `run:` / profiles + CLI).
public struct RunSession: Sendable {
    public var projectRoot: String
    public var disk: String?
    public var load: [(file: String, addr: UInt16)]
    public var start: UInt16
    public var maxInstructions: Int
    public var keys: [String]
    public var trace: Bool
    public var screen: Bool

    public init(
        projectRoot: String,
        disk: String? = nil,
        load: [(file: String, addr: UInt16)] = [],
        start: UInt16 = 0x1000,
        maxInstructions: Int = 1000,
        keys: [String] = [],
        trace: Bool = false,
        screen: Bool = false
    ) {
        self.projectRoot = projectRoot
        self.disk = disk
        self.load = load
        self.start = start
        self.maxInstructions = maxInstructions
        self.keys = keys
        self.trace = trace
        self.screen = screen
    }

    public static func from(
        projectRoot: String,
        config: ProjectConfig,
        profile: String? = nil,
        cliDisk: String? = nil,
        cliKeys: [String] = [],
        cliMaxInstructions: Int? = nil,
        cliTrace: Bool = false,
        cliScreen: Bool = false
    ) throws -> RunSession {
        let run = try config.resolvedRun(profile: profile)
        let root = (projectRoot as NSString).standardizingPath
        func resolve(_ path: String) -> String {
            if path.hasPrefix("/") { return path }
            return (root as NSString).appendingPathComponent(path)
        }
        return RunSession(
            projectRoot: root,
            disk: (cliDisk ?? run.disk).map(resolve),
            load: run.load.map { (resolve($0.file), $0.addr) },
            start: run.start ?? 0x1000,
            maxInstructions: cliMaxInstructions ?? run.maxInstructions ?? 1000,
            keys: cliKeys.isEmpty ? run.keys : cliKeys,
            trace: cliTrace || run.trace,
            screen: cliScreen || run.screen
        )
    }

    public var simulatorConfig: SimulatorConfig {
        SimulatorConfig(
            binaries: load.map { BinaryLoad(file: $0.file, loadAddress: $0.addr) },
            startAddress: start
        )
    }
}
