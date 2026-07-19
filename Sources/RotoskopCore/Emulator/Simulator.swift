import Foundation

/// Coordinates memory, CPU, and Apple II devices.
public final class Simulator {
    public let config: SimulatorConfig
    public let memory: Memory
    public let cpu: CPU

    private var keyboard: Keyboard?
    private var hardDrive: HardDrive?
    public private(set) var idleDetector: IdleDetector?

    public init(config: SimulatorConfig) {
        self.config = config
        self.memory = Memory()
        self.cpu = CPU(memory: memory)
    }

    /// Library-friendly init without a file config.
    public convenience init(startAddress: UInt16) {
        self.init(config: SimulatorConfig(binaries: [], startAddress: startAddress))
    }

    public func load() throws {
        idleDetector?.setSuppressed(true)
        defer {
            idleDetector?.setSuppressed(false)
            idleDetector?.wake()
        }
        // Clear vector tracking, then load (writes to $FFFE/$FFFF count as set), then reset regs.
        memory.markVectorsUnset()
        for binary in config.binaries {
            let data = try Data(contentsOf: URL(fileURLWithPath: binary.file))
            memory.loadBinary(data, at: binary.loadAddress)
        }
        memory.setResetVector(config.startAddress)
        cpu.reset(clearIRQVectorTracking: false)
    }

    public func setupKeyboard(inputStrings: [String]) {
        let kbd = Keyboard(inputStrings: inputStrings)
        keyboard = kbd
        memory.addReadHook(at: Keyboard.kbdData) { [unowned kbd] in kbd.readKbd() }
        memory.addReadHook(at: Keyboard.kbdStrobe) { [unowned kbd] in kbd.clearStrobe() }
        memory.addWriteHook(at: Keyboard.kbdStrobe) { [unowned kbd] _ in _ = kbd.clearStrobe() }
    }

    /// Interactive keyboard for app mode (call after `setupKeyboard` or alone).
    /// Enables experimental `$C000` idle detection for power save.
    public func ensureInteractiveKeyboard() -> Keyboard {
        if let keyboard { return keyboard }
        let kbd = Keyboard(inputStrings: [])
        keyboard = kbd
        let idle = IdleDetector()
        idleDetector = idle
        memory.onChangingNonStackWrite = { [weak idle] in idle?.noteChangingWrite() }
        memory.isEmulationIdle = { [weak idle] in idle?.isIdle ?? false }
        memory.addReadHook(at: Keyboard.kbdData) { [unowned kbd, unowned idle] in
            let value = kbd.readKbd()
            idle.noteKbdPoll(keyPending: (value & 0x80) != 0)
            return value
        }
        memory.addReadHook(at: Keyboard.kbdStrobe) { [unowned kbd] in kbd.clearStrobe() }
        memory.addWriteHook(at: Keyboard.kbdStrobe) { [unowned kbd] _ in _ = kbd.clearStrobe() }
        return kbd
    }

    public func setupHardDrive(imagePath: String) throws {
        let hd = try HardDrive(imagePath: imagePath)
        hardDrive = hd
        idleDetector?.setSuppressed(true)
        memory.loadBinary(hd.romBytes(), at: HardDrive.romBase)
        idleDetector?.setSuppressed(false)
        cpu.addPCHook(at: HardDrive.entryPoint) { [unowned self] in
            self.handleBlockCall()
        }
    }

    public func setupHardDrive(imageData: Data) {
        let hd = HardDrive(imageData: imageData)
        hardDrive = hd
        idleDetector?.setSuppressed(true)
        memory.loadBinary(hd.romBytes(), at: HardDrive.romBase)
        idleDetector?.setSuppressed(false)
        cpu.addPCHook(at: HardDrive.entryPoint) { [unowned self] in
            self.handleBlockCall()
        }
    }

    private func handleBlockCall() {
        guard let hardDrive else { return }
        do {
            let (aVal, carry) = try hardDrive.handleBlockCall(memory: memory)
            cpu.a = aVal
            cpu.setFlag(CPU.flagC, carry)
            cpu.opRTS()
        } catch {
            cpu.forceStop(.ioError(String(describing: error)))
        }
    }

    @discardableResult
    public func run(maxInstructions: Int = 1000, trace: Bool = false) -> StopReason {
        cpu.traceEnabled = trace
        return cpu.run(maxInstructions: maxInstructions)
    }

    @discardableResult
    public func run(maxCycles: Int, trace: Bool = false) -> StopReason {
        cpu.traceEnabled = trace
        return cpu.run(maxCycles: maxCycles)
    }

    public var instructionCount: Int { cpu.instructionCount }
    public var cycleCount: Int { cpu.cycleCount }
    public var trace: [String] { cpu.traceLog }

    public func dumpMemory(from start: UInt16, length: Int) -> [UInt8] {
        memory.dump(from: start, length: length)
    }

    public func dumpScreen() -> String {
        TextScreen.dump(memory)
    }

    public func dumpScreenCells() -> [[TextScreen.Cell]] {
        TextScreen.dumpCells(memory)
    }
}
