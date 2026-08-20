import Foundation

public enum TestStopExpectation: String, Equatable, Sendable {
    case any
    case success
    case limit
}

public struct TestSpec: Equatable, Sendable {
    public var name: String
    public var path: String
    public var keys: String?
    public var maxInstructions: Int?
    public var expects: [String]
    public var stop: TestStopExpectation

    public init(
        name: String,
        path: String,
        keys: String? = nil,
        maxInstructions: Int? = nil,
        expects: [String] = [],
        stop: TestStopExpectation = .any
    ) {
        self.name = name
        self.path = path
        self.keys = keys
        self.maxInstructions = maxInstructions
        self.expects = expects
        self.stop = stop
    }
}

public enum TestSpecParser {
    /// Returns nil when the file has no `; @test` directives.
    public static func parse(text: String, path: String) throws -> TestSpec? {
        let name = ((path as NSString).lastPathComponent as NSString).deletingPathExtension
        var keys: String?
        var maxInstructions: Int?
        var expects: [String] = []
        var stop = TestStopExpectation.any
        var sawDirective = false
        var sawStop = false

        for (index, rawLine) in text.split(separator: "\n", omittingEmptySubsequences: false).enumerated() {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard let body = directiveBody(line) else { continue }
            sawDirective = true
            let parts = body.split(maxSplits: 1, whereSeparator: { $0.isWhitespace })
            guard let verbPart = parts.first, !verbPart.isEmpty else {
                throw BuildError.invalidConfig("\(path):\(index + 1): empty @test directive")
            }
            let verb = String(verbPart)
            let rest = parts.count > 1 ? parts[1].trimmingCharacters(in: .whitespaces) : ""
            switch verb {
            case "keys":
                keys = rest
            case "max_instructions":
                guard let n = Int(rest) else {
                    throw BuildError.invalidConfig("\(path):\(index + 1): @test max_instructions needs an integer")
                }
                maxInstructions = n
            case "expect":
                guard !rest.isEmpty else {
                    throw BuildError.invalidConfig("\(path):\(index + 1): @test expect needs text")
                }
                expects.append(rest)
            case "stop":
                guard let value = TestStopExpectation(rawValue: rest) else {
                    throw BuildError.invalidConfig("\(path):\(index + 1): @test stop must be success, limit, or any")
                }
                stop = value
                sawStop = true
            default:
                throw BuildError.invalidConfig("\(path):\(index + 1): unknown @test directive '\(verb)'")
            }
        }

        guard sawDirective else { return nil }
        let effectiveStop = sawStop ? stop : .any
        if expects.isEmpty && (effectiveStop == .any) {
            throw BuildError.invalidConfig("\(path): test needs at least one @test expect or an explicit @test stop other than any")
        }
        return TestSpec(
            name: name,
            path: path,
            keys: keys,
            maxInstructions: maxInstructions,
            expects: expects,
            stop: effectiveStop
        )
    }

    public static func parse(file path: String) throws -> TestSpec? {
        let text = try String(contentsOfFile: path, encoding: .utf8)
        return try parse(text: text, path: path)
    }

    private static func directiveBody(_ line: String) -> String? {
        guard let semi = line.firstIndex(of: ";") else { return nil }
        var rest = line[semi...].dropFirst()
        while rest.first?.isWhitespace == true {
            rest = rest.dropFirst()
        }
        guard rest.hasPrefix("@test") else { return nil }
        rest = rest.dropFirst("@test".count)
        if rest.first?.isWhitespace == true {
            rest = rest.drop(while: { $0.isWhitespace })
        } else if !rest.isEmpty {
            return nil
        }
        return String(rest)
    }
}

public enum TestDiscovery {
    public static func discover(
        projectRoot: String,
        config: ProjectConfig,
        names: [String] = []
    ) throws -> [TestSpec] {
        if config.tests.files.isEmpty {
            throw BuildError.invalidConfig("no tests: files configured in rotoskop.yaml")
        }
        let root = (projectRoot as NSString).standardizingPath
        let paths = try SourceGlob.expand(patterns: config.tests.files, root: root)
        var specs: [TestSpec] = []
        var seen = Set<String>()
        for path in paths {
            guard let spec = try TestSpecParser.parse(file: path) else { continue }
            if !seen.insert(spec.name).inserted {
                throw BuildError.invalidConfig("duplicate test name '\(spec.name)'")
            }
            specs.append(spec)
        }
        if specs.isEmpty {
            throw BuildError.invalidConfig("no @test directives in \(config.tests.files.joined(separator: ", "))")
        }
        if names.isEmpty {
            return specs
        }
        let filtered = specs.filter { spec in
            names.contains { pattern in
                SourceGlob.matches(pattern, spec.name)
                    || SourceGlob.matches(pattern, (spec.path as NSString).lastPathComponent)
            }
        }
        if filtered.isEmpty {
            throw BuildError.invalidConfig("no tests match \(names.joined(separator: ", "))")
        }
        return filtered
    }
}
