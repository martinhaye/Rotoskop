import CoreText

#if canImport(UIKit)
import UIKit

/// Monospace coding face for the editor (DESIGN §3.2).
///
/// Horizontally condensed via a CTFont matrix so line height stays the same
/// while more columns fit on a phone-width screen. Tweak `widthScale` to taste.
enum EditorCodingFont {
    static let pointSize: CGFloat = 16
    /// 1.0 = natural system mono width; lower = slimmer.
    static let widthScale: CGFloat = 0.85

    static func make(size: CGFloat = pointSize, weight: UIFont.Weight = .regular) -> UIFont {
        let base = UIFont.monospacedSystemFont(ofSize: size, weight: weight)
        guard widthScale > 0, abs(widthScale - 1) > 0.001 else { return base }
        var matrix = CGAffineTransform(scaleX: widthScale, y: 1)
        let ct = CTFontCreateWithFontDescriptor(base.fontDescriptor, size, &matrix)
        return ct as UIFont
    }
}
#endif
