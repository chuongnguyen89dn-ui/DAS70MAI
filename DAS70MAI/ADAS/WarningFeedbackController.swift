import AudioToolbox
import Foundation
import UIKit

/// Presentation feedback for the current visual-risk heuristic.
/// This does not claim calibrated FCW/TTC behavior.
@MainActor
final class WarningFeedbackController {
    var soundEnabled = true
    var vibrationEnabled = true

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
            if vibrationEnabled { UIImpactFeedbackGenerator(style: .medium).impactOccurred() }
        case .warning:
            let now = Date()
            guard now.timeIntervalSince(lastWarningAt) >= warningCooldown else { return }
            lastWarningAt = now
            if vibrationEnabled { UINotificationFeedbackGenerator().notificationOccurred(.warning) }
            if soundEnabled { AudioServicesPlaySystemSound(1106) }
        }
    }

    func reset() {
        lastLevel = .clear
        lastWarningAt = .distantPast
    }
}
