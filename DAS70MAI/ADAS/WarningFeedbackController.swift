import AudioToolbox
import Foundation
import UIKit

/// Presentation feedback for the current visual-risk heuristic.
/// This does not claim calibrated FCW/TTC behavior.
@MainActor
final class WarningFeedbackController {
    private var lastLevel: ForwardRisk.Level = .clear
    private var lastWarningAt = Date.distantPast
    private let warningCooldown: TimeInterval = 1.5

    func update(level: ForwardRisk.Level) {
        guard level != lastLevel else { return }
        lastLevel = level

        switch level {
        case .clear:
            return
        case .caution:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .warning:
            let now = Date()
            guard now.timeIntervalSince(lastWarningAt) >= warningCooldown else { return }
            lastWarningAt = now
            UINotificationFeedbackGenerator().notificationOccurred(.warning)
            AudioServicesPlaySystemSound(1106)
        }
    }

    func reset() {
        lastLevel = .clear
        lastWarningAt = .distantPast
    }
}
