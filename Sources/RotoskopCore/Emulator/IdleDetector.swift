import Foundation

/// Experimental power-save: detect keyboard-wait loops via quiet `$C000` polls.
///
/// On each `$C000` read with no key pending, if fewer than `changeThreshold`
/// meaningful RAM writes occurred since the previous poll, a quiet timer runs;
/// after `idleSeconds` of continuous quiet polls, enter idle (CPU should stop).
/// A keypress calls `wake()`.
public final class IdleDetector: @unchecked Sendable {
    public static let changeThreshold = 4
    public static let defaultIdleSeconds: Double = 0.5

    /// Wall-clock quiet time before entering idle. Tests may set this to `0`.
    public var idleSeconds: Double = IdleDetector.defaultIdleSeconds

    private let lock = NSLock()
    private var writesSincePoll = 0
    private var quietStarted: DispatchTime?
    private var idle = false
    /// When true, ignore write / poll bookkeeping (e.g. during binary load).
    private var suppressed = false

    public var isIdle: Bool {
        lock.lock()
        defer { lock.unlock() }
        return idle
    }

    public func setSuppressed(_ value: Bool) {
        lock.lock()
        suppressed = value
        lock.unlock()
    }

    public func noteChangingWrite() {
        lock.lock()
        defer { lock.unlock() }
        if suppressed || idle { return }
        writesSincePoll += 1
    }

    /// Call on every `$C000` read. `keyPending` is true when bit 7 is set (key ready).
    /// Returns whether idle mode was entered on this poll.
    @discardableResult
    public func noteKbdPoll(keyPending: Bool = false) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if suppressed || idle { return false }

        defer { writesSincePoll = 0 }

        // Key ready — not waiting; reset quiet timer.
        if keyPending {
            quietStarted = nil
            return false
        }

        if writesSincePoll < Self.changeThreshold {
            let now = DispatchTime.now()
            if quietStarted == nil {
                quietStarted = now
            }
            if let start = quietStarted {
                let elapsed = Double(now.uptimeNanoseconds &- start.uptimeNanoseconds) / 1_000_000_000.0
                if elapsed >= idleSeconds {
                    idle = true
                }
            }
        } else {
            quietStarted = nil
        }
        return idle
    }

    /// Leave idle (e.g. key pressed) and clear counters.
    public func wake() {
        lock.lock()
        idle = false
        quietStarted = nil
        writesSincePoll = 0
        lock.unlock()
    }
}
