import SwiftUI

/// Visual road/lane guide for the current test build.
/// This is deliberately labelled as a guide: it is not camera-derived lane detection yet.
struct LaneGuideOverlay: View {
    var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            ZStack {
                Path { path in
                    path.move(to: CGPoint(x: w * 0.14, y: h * 0.98))
                    path.addLine(to: CGPoint(x: w * 0.43, y: h * 0.48))
                }
                .stroke(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [12, 10]))

                Path { path in
                    path.move(to: CGPoint(x: w * 0.86, y: h * 0.98))
                    path.addLine(to: CGPoint(x: w * 0.57, y: h * 0.48))
                }
                .stroke(.yellow.opacity(0.9), style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [12, 10]))

                Text("LANE GUIDE")
                    .font(.caption2.bold())
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.black.opacity(0.55))
                    .clipShape(Capsule())
                    .position(x: w * 0.5, y: h * 0.44)
            }
        }
        .allowsHitTesting(false)
    }
}
