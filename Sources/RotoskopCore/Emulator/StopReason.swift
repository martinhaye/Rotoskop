/// Why the emulator stopped. Hosts (CLI / UI) branch on this.
public enum StopReason: Equatable, Sendable {
    /// PC reached `$FFF9` (cc65 / runix success halt).
    case success
    /// Soft pause for chunked run loops (instruction or cycle batch cap).
    case instructionLimit
    /// `BRK` with IRQ/BRK vector never written since reset.
    case unhandledBRK
    /// Official 6502 illegal / unimplemented opcode.
    case illegalOpcode(UInt8)
    /// Host requested stop (UI / library).
    case explicitStop
    /// Device I/O failure (e.g. disk).
    case ioError(String)

    public var isSuccess: Bool {
        if case .success = self { return true }
        return false
    }
}
