import Foundation

struct RoadObjectFilter {
    private static let relevantLabels: Set<String> = [
        "person", "bicycle", "car", "motorcycle", "bus", "truck"
    ]

    static func relevant(_ detections: [ADASDetection], minimumConfidence: Float = 0.35) -> [ADASDetection] {
        detections.filter {
            $0.confidence >= minimumConfidence && relevantLabels.contains($0.label.lowercased())
        }
    }
}
