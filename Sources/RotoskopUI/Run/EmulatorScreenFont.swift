import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Monospace face for the 40-column emulator screen.
///
/// Horizontally condensed (same trick as `EditorCodingFont`) so a full Apple II
/// line fits on a phone-width screen without shrinking line height.
enum EmulatorScreenFont {
    /// Target columns for the text screen (`TextScreen.cols`).
    static let columns = 40
    /// Extra slack so 40 chars don't kiss the padding edge.
    private static let widthSlack: CGFloat = 0.98

    #if canImport(UIKit)
    static func make(fittingWidth: CGFloat) -> UIFont {
        let pointSize = UIFont.preferredFont(forTextStyle: .body).pointSize
        let base = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let scale = horizontalScale(base: base, fittingWidth: fittingWidth, pointSize: pointSize)
        guard scale < 0.999 else { return base }
        var matrix = CGAffineTransform(scaleX: scale, y: 1)
        let ct = CTFontCreateWithFontDescriptor(base.fontDescriptor, pointSize, &matrix)
        return ct as UIFont
    }

    private static func horizontalScale(base: UIFont, fittingWidth: CGFloat, pointSize: CGFloat) -> CGFloat {
        let sample = String(repeating: "M", count: columns) as NSString
        let natural = sample.size(withAttributes: [.font: base]).width
        guard natural > 0, fittingWidth > 0 else { return 1 }
        return min(1, (fittingWidth * widthSlack) / natural)
    }
    #elseif canImport(AppKit)
    static func make(fittingWidth: CGFloat) -> NSFont {
        let pointSize = NSFont.preferredFont(forTextStyle: .body).pointSize
        let base = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let scale = horizontalScale(base: base, fittingWidth: fittingWidth)
        guard scale < 0.999 else { return base }
        var matrix = CGAffineTransform(scaleX: scale, y: 1)
        let ct = CTFontCreateWithFontDescriptor(base.fontDescriptor, pointSize, &matrix)
        return ct as NSFont
    }

    private static func horizontalScale(base: NSFont, fittingWidth: CGFloat) -> CGFloat {
        let sample = String(repeating: "M", count: columns) as NSString
        let natural = sample.size(withAttributes: [.font: base]).width
        guard natural > 0, fittingWidth > 0 else { return 1 }
        return min(1, (fittingWidth * widthSlack) / natural)
    }
    #endif
}
