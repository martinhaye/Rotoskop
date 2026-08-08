import Foundation
import Testing
@testable import RotoskopUI

@Suite("Assembly keyboard layout")
struct AssemblyKeyboardLayoutTests {
    @Test func topRowIsFixed() {
        #expect(AssemblyKeyboardLayout.topRow == [
            "1", "#", "$", "(", ")", ",", "-", "_", "+", ";",
        ])
    }
}
