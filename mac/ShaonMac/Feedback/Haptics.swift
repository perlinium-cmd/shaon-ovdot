import AppKit

/// Trackpad haptics. Macs only "feel" these while a finger is on the trackpad.
@MainActor
enum Haptics {
    enum Strength: String, CaseIterable { case normal, strong }

    private static var last = Date.distantPast
    private static let minGap: TimeInterval = 0.015   // fast scrolling stays distinct teeth

    /// One "tooth". `accent` = stronger click (round hour, ends of the list).
    static func tick(accent: Bool = false, strength: Strength = .normal) {
        let now = Date()
        guard now.timeIntervalSince(last) >= minGap else { return }
        last = now
        // .levelChange is the strongest pattern macOS offers; .alignment is barely perceptible while scrolling.
        // "normal" = levelChange on every tooth; "strong" adds a generic pulse right after for extra punch.
        let performer = NSHapticFeedbackManager.defaultPerformer
        performer.perform(.levelChange, performanceTime: .now)
        if accent || strength == .strong { performer.perform(.generic, performanceTime: .now) }
    }
}
