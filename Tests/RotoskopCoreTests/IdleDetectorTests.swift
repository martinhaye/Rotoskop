import Foundation
import Testing
@testable import RotoskopCore

@Suite("Idle detector")
struct IdleDetectorTests {
    @Test func busyPollDoesNotIdle() {
        let mem = Memory()
        let idle = IdleDetector()
        idle.idleSeconds = 0
        mem.onChangingNonStackWrite = { idle.noteChangingWrite() }

        for i in 0..<IdleDetector.changeThreshold {
            mem.write(0x0200 &+ UInt16(i), UInt8(i &+ 1))
        }
        #expect(!idle.noteKbdPoll())
        #expect(!idle.isIdle)
    }

    @Test func stackWritesDoNotCountAsBusy() {
        let mem = Memory()
        let idle = IdleDetector()
        idle.idleSeconds = 0
        mem.onChangingNonStackWrite = { idle.noteChangingWrite() }

        mem.write(0x0100, 0x55)
        mem.write(0x01FF, 0x66)
        #expect(idle.noteKbdPoll())
        #expect(idle.isIdle)
    }

    @Test func sameValueWriteIsIgnored() {
        let mem = Memory()
        let idle = IdleDetector()
        idle.idleSeconds = 0
        mem.onChangingNonStackWrite = { idle.noteChangingWrite() }

        mem.write(0x0200, 0x11)
        mem.write(0x0200, 0x11)
        // Only one meaningful write → still quiet → idle with idleSeconds == 0.
        #expect(idle.noteKbdPoll())
        #expect(idle.isIdle)
    }

    @Test func keyPendingResetsQuietTimer() {
        let idle = IdleDetector()
        idle.idleSeconds = 0
        #expect(!idle.noteKbdPoll(keyPending: true))
        #expect(!idle.isIdle)
        #expect(idle.noteKbdPoll(keyPending: false))
        #expect(idle.isIdle)
    }

    @Test func quietPollsEnterIdleAfterDurationAndWakeClears() {
        let idle = IdleDetector()
        idle.idleSeconds = 0.05
        #expect(!idle.noteKbdPoll())
        #expect(!idle.isIdle)
        Thread.sleep(forTimeInterval: 0.06)
        #expect(idle.noteKbdPoll())
        #expect(idle.isIdle)

        idle.wake()
        #expect(!idle.isIdle)
    }

    @Test func busyPollResetsQuietTimer() {
        let mem = Memory()
        let idle = IdleDetector()
        idle.idleSeconds = 0.05
        mem.onChangingNonStackWrite = { idle.noteChangingWrite() }

        #expect(!idle.noteKbdPoll()) // start quiet timer
        Thread.sleep(forTimeInterval: 0.03)
        for i in 0..<IdleDetector.changeThreshold {
            mem.write(0x0400 &+ UInt16(i), UInt8(i &+ 1))
        }
        #expect(!idle.noteKbdPoll()) // busy → clear quiet timer
        #expect(!idle.noteKbdPoll()) // restart quiet at t=0
        #expect(!idle.isIdle)
        Thread.sleep(forTimeInterval: 0.06)
        #expect(idle.noteKbdPoll())
        #expect(idle.isIdle)
    }

    @Test func interactiveWaitLoopIdlesUntilKey() {
        let sim = Simulator(startAddress: 0x1000)
        let kbd = sim.ensureInteractiveKeyboard()
        let prog: [UInt8] = [
            0xAD, 0x00, 0xC0, // LDA $C000
            0x10, 0xFB,       // BPL *-3
            0x4C, 0xF9, 0xFF, // JMP $FFF9
        ]
        sim.memory.loadBinary(prog, at: 0x1000)
        sim.memory.setResetVector(0x1000)
        sim.cpu.reset(clearIRQVectorTracking: false)
        sim.idleDetector?.wake()
        sim.idleDetector?.idleSeconds = 0

        var enteredIdle = false
        for _ in 0..<40 {
            _ = sim.run(maxCycles: 2_000)
            if sim.idleDetector?.isIdle == true {
                enteredIdle = true
                break
            }
        }
        #expect(enteredIdle)

        kbd.injectKey(UInt8(ascii: "Z"))
        sim.idleDetector?.wake()
        #expect(sim.idleDetector?.isIdle == false)

        var reason: StopReason = .instructionLimit
        for _ in 0..<20 {
            reason = sim.run(maxCycles: 500)
            if reason == .success { break }
        }
        #expect(reason == .success)
    }
}
