import Foundation

/// Stabilizes the visual risk heuristic so a single noisy detection does not immediately
/// raise or clear a warning. This is warning presentation logic, not calibrated FCW/TTC.
struct WarningDebouncer: Sendable {
    private(set) var displayedLevel: ForwardRisk.Level = .clear
    private var pendingLevel: ForwardRisk.Level = .clear
    private var pendingCount = 0

    mutating func update(with risk: ForwardRisk) -> ForwardRisk.Level {
        if risk.level == displayedLevel {
            pendingLevel = displayedLevel
            pendingCount = 0
            return displayedLevel
        }

        if risk.level != pendingLevel {
            pendingLevel = risk.level
            pendingCount = 1
        } else {
            pendingCount += 1
        }

        let requiredFrames: Int
        switch risk.level {
        case .warning: requiredFrames = 2
        case .caution: requiredFrames = 3
        case .clear: requiredFrames = 5
        }

        if pendingCount >= requiredFrames {
            displayedLevel = pendingLevel
            pendingCount = 0
        }
        return displayedLevel
    }

    mutating func reset() {
        displayedLevel = .clear
        pendingLevel = .clear
        pendingCount = 0
    }
}
