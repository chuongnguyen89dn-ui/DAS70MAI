import Foundation

struct ForwardRisk: Sendable {
    enum Level: Sendable { case clear, caution, warning }
    let level: Level
    let object: ADASDetection?
}

struct ForwardRiskEvaluator {
    /// Demo visual-risk gate only. This is not verified TTC/FCW until calibrated with camera geometry and speed.
    static func evaluate(_ detections: [ADASDetection]) -> ForwardRisk {
        let candidates = RoadObjectFilter.relevant(detections).filter { detection in
            let centerX = detection.boundingBox.midX
            return centerX > 0.30 && centerX < 0.70
        }

        guard let nearest = candidates.max(by: { area($0.boundingBox) < area($1.boundingBox) }) else {
            return ForwardRisk(level: .clear, object: nil)
        }

        let boxArea = area(nearest.boundingBox)
        if boxArea > 0.20 { return ForwardRisk(level: .warning, object: nearest) }
        if boxArea > 0.08 { return ForwardRisk(level: .caution, object: nearest) }
        return ForwardRisk(level: .clear, object: nearest)
    }

    private static func area(_ rect: CGRect) -> CGFloat { rect.width * rect.height }
}
