//
//  ContentView.swift
//  Rotoskop (iOS app shell)
//
//  A throwaway demo view: it hand-assembles a tiny program that writes "HELLO"
//  to the text screen, runs it on the emulator core, and renders the decoded
//  40×24 screen. Its only purpose today is to prove the app is correctly wired
//  to the `RotoskopEmulator` package. It will be replaced by the real UI.
//

import SwiftUI
import RotoskopEmulator

struct ContentView: View {
    @State private var screen: [String] = []
    @State private var registers = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Rotoskop")
                .font(.largeTitle.bold())
            Text(registers)
                .font(.system(.footnote, design: .monospaced))
            ScrollView {
                Text(screen.joined(separator: "\n"))
                    .font(.system(.body, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .background(Color.black)
            .foregroundColor(.green)
        }
        .padding()
        .onAppear(perform: runDemo)
    }

    private func runDemo() {
        let machine = Machine()

        // Emit "HELLO" (high-bit-set Apple II chars) to the top-left of the
        // text screen, one STA per character, then BRK.
        var program: [UInt8] = []
        let base: UInt16 = 0x0400
        for (i, ascii) in "HELLO".utf8.enumerated() {
            let addr = base + UInt16(i)
            program += [0xA9, ascii | 0x80]                       // LDA #char
            program += [0x8D, UInt8(addr & 0xFF), UInt8(addr >> 8)] // STA addr
        }
        program += [0x00] // BRK

        machine.load(program)
        machine.run()

        screen = machine.screenLines()
        let s = machine.registerSnapshot()
        registers = String(format: "A=%02X X=%02X Y=%02X PC=%04X cycles=%d",
                           s.a, s.x, s.y, s.pc, Int(s.cycles))
    }
}

#Preview {
    ContentView()
}
