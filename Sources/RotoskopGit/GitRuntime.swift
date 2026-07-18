import Foundation
import libgit2

/// Process-wide libgit2 init/shutdown (refcounted).
enum GitRuntime {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var depth = 0

    static func initialize() {
        lock.lock()
        defer { lock.unlock() }
        if depth == 0 {
            git_libgit2_init()
        }
        depth += 1
    }

    static func shutdown() {
        lock.lock()
        defer { lock.unlock() }
        guard depth > 0 else { return }
        depth -= 1
        if depth == 0 {
            git_libgit2_shutdown()
        }
    }
}
