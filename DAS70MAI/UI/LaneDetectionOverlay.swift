import SwiftUI

struct LaneDetectionOverlay: View {
    let segments: [LaneSegment]

    var body: some View {
        GeometryReader { geometry in
            Path { path in
                for segment in segments {
                    path.move(to: CGPoint(x: segment.start.x * geometry.size.width,
                                          y: segment.start.y * geometry.size.height))
                    path.addLine(to: CGPoint(x: segment.end.x * geometry.size.width,
                                             y: segment.end.y * geometry.size.height))
                }
            }
            .stroke(.cyan, style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
        .allowsHitTesting(false)
    }
}
