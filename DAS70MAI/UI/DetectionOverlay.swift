import SwiftUI

struct DetectionOverlay: View {
    let detections: [ADASDetection]

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = displayRect(for: detection.boundingBox, in: geometry.size)
                ZStack(alignment: .topLeading) {
                    Rectangle()
                        .stroke(.yellow, lineWidth: 2)
                        .frame(width: rect.width, height: rect.height)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.bold())
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .background(.yellow)
                        .foregroundStyle(.black)
                }
                .position(x: rect.midX, y: rect.midY)
            }
        }
        .allowsHitTesting(false)
    }

    private func displayRect(for normalized: CGRect, in size: CGSize) -> CGRect {
        CGRect(
            x: normalized.minX * size.width,
            y: (1 - normalized.maxY) * size.height,
            width: normalized.width * size.width,
            height: normalized.height * size.height
        )
    }
}
