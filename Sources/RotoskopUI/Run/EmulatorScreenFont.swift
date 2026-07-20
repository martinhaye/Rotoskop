import CoreText
import SwiftUI

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

/// Monospace face for the 40×24 emulator screen.
///
/// Condensed horizontally to fit 40 columns, and slightly tightened vertically so
/// all 24 rows fit in the available height when possible.
enum EmulatorScreenFont {
    /// Target columns for the text screen (`TextScreen.cols`).
    static let columns = 40
    /// Target rows for the text screen (`TextScreen.rows`).
    static let rows = 24
    /// Extra slack so 40 chars don't kiss the padding edge.
    private static let widthSlack: CGFloat = 0.98
    /// Slight vertical tighten vs natural line height.
    private static let verticalTighten: CGFloat = 0.92

    #if canImport(UIKit)
    static func make(fittingWidth: CGFloat, fittingHeight: CGFloat? = nil) -> UIFont {
        let preferred = UIFont.preferredFont(forTextStyle: .body).pointSize
        let pointSize = Self.pointSize(
            preferred: preferred,
            fittingWidth: fittingWidth,
            fittingHeight: fittingHeight
        )
        let base = UIFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let xScale = horizontalScale(base: base, fittingWidth: fittingWidth)
        let yScale = verticalTighten
        guard xScale < 0.999 || yScale < 0.999 else { return base }
        var matrix = CGAffineTransform(scaleX: min(1, xScale), y: yScale)
        let ct = CTFontCreateWithFontDescriptor(base.fontDescriptor, pointSize, &matrix)
        return ct as UIFont
    }

    private static func pointSize(
        preferred: CGFloat,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat?
    ) -> CGFloat {
        var size = preferred
        if let fittingHeight, fittingHeight > 0 {
            // Approximate: line height ≈ pointSize for monospaced system font.
            let maxByHeight = fittingHeight / (CGFloat(rows) * verticalTighten)
            size = min(size, maxByHeight)
        }
        // Also shrink if width alone would force extreme horizontal squash.
        if fittingWidth > 0 {
            let probe = UIFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let natural = (String(repeating: "M", count: columns) as NSString)
                .size(withAttributes: [.font: probe]).width
            if natural > 0 {
                let needed = (fittingWidth * widthSlack) / natural
                if needed < 0.75 {
                    size *= needed / 0.75
                }
            }
        }
        return max(8, size)
    }

    private static func horizontalScale(base: UIFont, fittingWidth: CGFloat) -> CGFloat {
        let sample = String(repeating: "M", count: columns) as NSString
        let natural = sample.size(withAttributes: [.font: base]).width
        guard natural > 0, fittingWidth > 0 else { return 1 }
        return min(1, (fittingWidth * widthSlack) / natural)
    }
    #elseif canImport(AppKit)
    static func make(fittingWidth: CGFloat, fittingHeight: CGFloat? = nil) -> NSFont {
        let preferred = NSFont.preferredFont(forTextStyle: .body).pointSize
        let pointSize = Self.pointSize(
            preferred: preferred,
            fittingWidth: fittingWidth,
            fittingHeight: fittingHeight
        )
        let base = NSFont.monospacedSystemFont(ofSize: pointSize, weight: .regular)
        let xScale = horizontalScale(base: base, fittingWidth: fittingWidth)
        let yScale = verticalTighten
        guard xScale < 0.999 || yScale < 0.999 else { return base }
        var matrix = CGAffineTransform(scaleX: min(1, xScale), y: yScale)
        let ct = CTFontCreateWithFontDescriptor(base.fontDescriptor, pointSize, &matrix)
        return ct as NSFont
    }

    private static func pointSize(
        preferred: CGFloat,
        fittingWidth: CGFloat,
        fittingHeight: CGFloat?
    ) -> CGFloat {
        var size = preferred
        if let fittingHeight, fittingHeight > 0 {
            let maxByHeight = fittingHeight / (CGFloat(rows) * verticalTighten)
            size = min(size, maxByHeight)
        }
        if fittingWidth > 0 {
            let probe = NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
            let natural = (String(repeating: "M", count: columns) as NSString)
                .size(withAttributes: [.font: probe]).width
            if natural > 0 {
                let needed = (fittingWidth * widthSlack) / natural
                if needed < 0.75 {
                    size *= needed / 0.75
                }
            }
        }
        return max(8, size)
    }

    private static func horizontalScale(base: NSFont, fittingWidth: CGFloat) -> CGFloat {
        let sample = String(repeating: "M", count: columns) as NSString
        let natural = sample.size(withAttributes: [.font: base]).width
        guard natural > 0, fittingWidth > 0 else { return 1 }
        return min(1, (fittingWidth * widthSlack) / natural)
    }
    #endif
}
