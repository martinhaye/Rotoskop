import Foundation

/// Persisted emulator clock preference (Settings sheet).
enum EmulationPreferences {
    static let clockMHzKey = "rotoskop.emulationClockMHz"
    static let minMHz = 0.5
    static let maxMHz = 10.0
    static let defaultMHz = 1.0
    /// Sticky snap targets on the Settings slider.
    static let detentMHz: [Double] = [1.0, 1.8]
    static let detentSnapDistance = 0.12

    static var clockMHz: Double {
        get {
            let raw = UserDefaults.standard.object(forKey: clockMHzKey) as? Double ?? defaultMHz
            return clamp(raw)
        }
        set {
            UserDefaults.standard.set(clamp(newValue), forKey: clockMHzKey)
        }
    }

    static func clamp(_ value: Double) -> Double {
        min(maxMHz, max(minMHz, value))
    }

    /// Snap to sticky detents when close enough.
    static func snap(_ value: Double) -> Double {
        let clamped = clamp(value)
        for detent in detentMHz {
            if abs(clamped - detent) <= detentSnapDistance {
                return detent
            }
        }
        return clamped
    }

    static func formatMHz(_ value: Double) -> String {
        String(format: "%.2f MHz", value)
    }

    /// Effective clock readout while running: nearest 0.1 MHz.
    static func formatEffectiveMHz(_ value: Double) -> String {
        let rounded = (value * 10).rounded() / 10
        return String(format: "%.1f MHz", rounded)
    }
}
