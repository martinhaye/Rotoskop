import Foundation

public struct TestCaseResult: Sendable {
    public var spec: TestSpec
    public var passed: Bool
    public var screen: String
    public var stopReason: StopReason?
    public var instructionCount: Int
    public var missingExpects: [String]
    public var stopMismatch: String?
    public var error: String?

    public init(
        spec: TestSpec,
        passed: Bool,
        screen: String = "",
        stopReason: StopReason? = nil,
        instructionCount: Int = 0,
        missingExpects: [String] = [],
        stopMismatch: String? = nil,
        error: String? = nil
    ) {
        self.spec = spec
        self.passed = passed
        self.screen = screen
        self.stopReason = stopReason
        self.instructionCount = instructionCount
        self.missingExpects = missingExpects
        self.stopMismatch = stopMismatch
        self.error = error
    }
}

public struct TestRunSummary: Sendable {
    public var results: [TestCaseResult]

    public var passedCount: Int { results.filter(\.passed).count }
    public var failedCount: Int { results.filter { !$0.passed }.count }
    public var succeeded: Bool { failedCount == 0 && !results.isEmpty }

    public init(results: [TestCaseResult]) {
        self.results = results
    }
}

public enum TestRunner {
    public static func run(spec: TestSpec, session: RunSession) -> TestCaseResult {
        var session = session
        session.keys = spec.keys.map { [$0] } ?? []
        if let max = spec.maxInstructions {
            session.maxInstructions = max
        }

        let sim = Simulator(config: session.simulatorConfig)
        if !session.keys.isEmpty {
            sim.setupKeyboard(inputStrings: session.keys)
        }
        if let diskPath = session.disk {
            do {
                try sim.setupHardDrive(imagePath: diskPath)
            } catch {
                return TestCaseResult(spec: spec, passed: false, error: "Cannot open disk image: \(error)")
            }
        }
        do {
            try sim.load()
        } catch {
            return TestCaseResult(spec: spec, passed: false, error: "\(error)")
        }

        let reason = sim.run(maxInstructions: session.maxInstructions, trace: false)
        let screen = sim.dumpScreen()
        let missing = spec.expects.filter { !screen.contains($0) }
        let stopMismatch = mismatch(expected: spec.stop, actual: reason)
        let passed = missing.isEmpty && stopMismatch == nil
        return TestCaseResult(
            spec: spec,
            passed: passed,
            screen: screen,
            stopReason: reason,
            instructionCount: sim.instructionCount,
            missingExpects: missing,
            stopMismatch: stopMismatch
        )
    }

    public static func run(
        projectRoot: String,
        config: ProjectConfig,
        names: [String] = []
    ) throws -> TestRunSummary {
        let specs = try TestDiscovery.discover(projectRoot: projectRoot, config: config, names: names)
        let base = try RunSession.from(projectRoot: projectRoot, config: config, profile: nil)
        return TestRunSummary(results: specs.map { run(spec: $0, session: base) })
    }

    public static func formatFailure(_ result: TestCaseResult) -> String {
        var lines: [String] = []
        if let error = result.error {
            lines.append("  error: \(error)")
        }
        for exp in result.missingExpects {
            lines.append("  missing expect: \(exp)")
        }
        if let stop = result.stopMismatch {
            lines.append("  \(stop)")
        }
        if let reason = result.stopReason {
            lines.append("  stop: \(describe(reason))")
        }
        if !result.screen.isEmpty {
            lines.append("  screen:")
            for row in result.screen.split(separator: "\n", omittingEmptySubsequences: false) {
                lines.append("    \(row)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func mismatch(expected: TestStopExpectation, actual: StopReason) -> String? {
        switch expected {
        case .any:
            return nil
        case .success:
            if case .success = actual { return nil }
            return "expected stop success, got \(describe(actual))"
        case .limit:
            if case .instructionLimit = actual { return nil }
            return "expected stop limit, got \(describe(actual))"
        }
    }

    private static func describe(_ reason: StopReason) -> String {
        switch reason {
        case .success: return "success"
        case .instructionLimit: return "limit"
        case .unhandledBRK: return "unhandled BRK"
        case .illegalOpcode(let op): return String(format: "illegal opcode $%02X", op)
        case .explicitStop: return "explicit stop"
        case .ioError(let msg): return "I/O error: \(msg)"
        }
    }
}
