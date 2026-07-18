import Foundation

public struct SourceLocation: Equatable, Sendable, CustomStringConvertible {
    public var file: String
    public var line: Int
    public var column: Int

    public init(file: String, line: Int, column: Int = 1) {
        self.file = file
        self.line = line
        self.column = column
    }

    public var description: String { "\(file):\(line):\(column)" }
}

public struct Diagnostic: Equatable, Sendable, CustomStringConvertible {
    public enum Severity: Equatable, Sendable {
        case error
        case warning
    }

    public var severity: Severity
    public var message: String
    public var location: SourceLocation?

    public init(_ severity: Severity, _ message: String, at location: SourceLocation? = nil) {
        self.severity = severity
        self.message = message
        self.location = location
    }

    public var description: String {
        if let location {
            return "\(location): \(severity == .error ? "error" : "warning"): \(message)"
        }
        return "\(severity == .error ? "error" : "warning"): \(message)"
    }
}

public struct AssembleResult: Sendable {
    public var binary: [UInt8]
    /// Lowest address emitted (from `.org`); binary[0] maps to this address.
    public var baseAddress: UInt16
    public var listing: String
    public var diagnostics: [Diagnostic]

    public var succeeded: Bool { !diagnostics.contains { $0.severity == .error } }
}

public struct AssembleOptions: Sendable {
    public var includePaths: [String]
    public var generateListing: Bool

    public init(includePaths: [String] = [], generateListing: Bool = true) {
        self.includePaths = includePaths
        self.generateListing = generateListing
    }
}
