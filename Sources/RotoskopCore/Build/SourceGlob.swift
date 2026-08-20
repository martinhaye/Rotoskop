import Foundation

/// Simple `*` / `?` glob matching and expansion (assemble sources, test files, CLI stem filters).
public enum SourceGlob {
    public static func matches(_ pattern: String, _ name: String) -> Bool {
        globMatch(Substring(pattern), Substring(name))
    }

    public static func expand(
        patterns: [String],
        root: String,
        fileManager: FileManager = .default,
        missingIsError: Bool = true
    ) throws -> [String] {
        var result: [String] = []
        for pattern in patterns {
            if pattern.contains("*") || pattern.contains("?") {
                let ns = pattern as NSString
                let dirPart = ns.deletingLastPathComponent
                let filePat = ns.lastPathComponent
                let dir = dirPart.isEmpty || dirPart == "."
                    ? root
                    : abs(dirPart, root: root)
                guard fileManager.fileExists(atPath: dir) else {
                    if missingIsError {
                        throw BuildError.io("source not found: \(pattern)")
                    }
                    continue
                }
                let files = try fileManager.contentsOfDirectory(atPath: dir)
                for f in files.filter({ matches(filePat, $0) }).sorted() {
                    result.append((dir as NSString).appendingPathComponent(f))
                }
            } else {
                let path = abs(pattern, root: root)
                if fileManager.fileExists(atPath: path) {
                    result.append(path)
                } else if missingIsError {
                    throw BuildError.io("source not found: \(pattern)")
                }
            }
        }
        return result
    }

    private static func abs(_ rel: String, root: String) -> String {
        if rel.hasPrefix("/") { return rel }
        return (root as NSString).appendingPathComponent(rel)
    }

    private static func globMatch(_ pattern: Substring, _ name: Substring) -> Bool {
        var pi = pattern.startIndex
        var ni = name.startIndex
        while pi < pattern.endIndex {
            if pattern[pi] == "*" {
                let after = pattern.index(after: pi)
                if after == pattern.endIndex { return true }
                var nj = ni
                while true {
                    if globMatch(pattern[after...], name[nj...]) { return true }
                    if nj == name.endIndex { return false }
                    nj = name.index(after: nj)
                }
            }
            if ni == name.endIndex { return false }
            if pattern[pi] != "?" && pattern[pi] != name[ni] { return false }
            pi = pattern.index(after: pi)
            ni = name.index(after: ni)
        }
        return ni == name.endIndex
    }
}
