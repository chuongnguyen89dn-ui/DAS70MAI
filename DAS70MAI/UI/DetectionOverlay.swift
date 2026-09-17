import SwiftUI

struct DetectionOverlay: View {
    let detections: [ADASDetection]
    /// RearCameraSource currently captures 1280x720. Keep this explicit until source metadata
    /// is carried with every frame/result (required later for A500S resolutions).
    var imageSize = CGSize(width: 1280, height: 720)

    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let rect = aspectFillDisplayRect(
                    for: detection.boundingBox,
                    imageSize: imageSize,
                    viewSize: geometry.size
                )
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

    /// Port of UltralyticsYOLO's YOLOView aspect-fill box transform.
    /// Ultralytics `xywhn` uses top-left display coordinates, so no Vision-style Y flip is applied.
    private func aspectFillDisplayRect(
        for normalizedRect: CGRect,
        imageSize: CGSize,
        viewSize: CGSize
    ) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0,
              viewSize.width > 0, viewSize.height > 0 else { return .zero }

        let scale = max(viewSize.width / imageSize.width, viewSize.height / imageSize.height)
        let scaledImageSize = CGSize(width: imageSize.width * scale, height: imageSize.height * scale)
        let offset = CGPoint(
            x: (scaledImageSize.width - viewSize.width) / 2,
            y: (scaledImageSize.height - viewSize.height) / 2
        )
        return CGRect(
            x: normalizedRect.minX * imageSize.width * scale - offset.x,
            y: normalizedRect.minY * imageSize.height * scale - offset.y,
            width: normalizedRect.width * imageSize.width * scale,
            height: normalizedRect.height * imageSize.height * scale
        )
    }
}
