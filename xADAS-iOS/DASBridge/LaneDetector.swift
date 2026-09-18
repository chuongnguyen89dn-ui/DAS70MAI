import CoreImage
import CoreVideo
import Vision

struct LaneSegment: Identifiable, Sendable {
    let id = UUID()
    let start: CGPoint
    let end: CGPoint
}

/// Lightweight camera-derived lane candidate detector using Vision contours.
/// It intentionally returns only long, lower-frame diagonal segments; this is
/// a visual lane aid, not a calibrated lane-departure system.
final class LaneDetector: @unchecked Sendable {
    private let request = VNDetectContoursRequest()

    init() {
        request.contrastAdjustment = 1.5
        request.detectsDarkOnLight = false
        request.maximumImageDimension = 512
    }

    func detect(pixelBuffer: CVPixelBuffer) -> [LaneSegment] {
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }
        guard let observation = request.results?.first else { return [] }

        var candidates: [LaneSegment] = []
        for contour in observation.topLevelContours {
            let points = contour.normalizedPoints
            guard points.count >= 2 else { continue }
            for index in 1..<points.count {
                let a = CGPoint(x: CGFloat(points[index - 1].x), y: 1 - CGFloat(points[index - 1].y))
                let b = CGPoint(x: CGFloat(points[index].x), y: 1 - CGFloat(points[index].y))
                let dx = abs(b.x - a.x)
                let dy = abs(b.y - a.y)
                guard max(a.y, b.y) > 0.48, dy > 0.055, dy > dx * 0.55 else { continue }
                let midX = (a.x + b.x) * 0.5
                guard midX > 0.08, midX < 0.92 else { continue }
                candidates.append(LaneSegment(start: a, end: b))
            }
        }
        return Array(candidates.sorted { lhs, rhs in
            hypot(lhs.end.x - lhs.start.x, lhs.end.y - lhs.start.y) > hypot(rhs.end.x - rhs.start.x, rhs.end.y - rhs.start.y)
        }.prefix(20))
    }
}
