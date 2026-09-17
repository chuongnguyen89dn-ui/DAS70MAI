import CoreImage
import CoreVideo
import Foundation
import UltralyticsYOLO

actor UltralyticsDetectionEngine: ADASInferenceEngine {
    private var model: YOLO?
    private var loading = false

    func infer(pixelBuffer: CVPixelBuffer, source: VideoSourceKind) async throws -> ADASFrameResult {
        let yolo = try await loadedModel()
        let result = yolo(CIImage(cvPixelBuffer: pixelBuffer))
        let detections = result.boxes.map { box in
            ADASDetection(
                id: UUID(),
                label: box.cls,
                confidence: box.conf,
                boundingBox: box.xywhn
            )
        }
        return ADASFrameResult(
            source: source,
            detections: RoadObjectFilter.relevant(detections),
            processedAt: .now
        )
    }

    private func loadedModel() async throws -> YOLO {
        if let model, model.isLoaded { return model }
        if loading {
            while loading {
                try await Task.sleep(for: .milliseconds(50))
            }
            if let model, model.isLoaded { return model }
            throw EngineError.modelLoadFailed
        }

        loading = true
        defer { loading = false }

        let remote = URL(string: "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo26n.mlpackage.zip")!
        return try await withCheckedThrowingContinuation { continuation in
            _ = YOLO(url: remote, task: .detect, useGpu: true, numItemsThreshold: 30) { [weak self] result in
                switch result {
                case .success(let loaded):
                    loaded.setConfidenceThreshold(0.35)
                    self?.model = loaded
                    continuation.resume(returning: loaded)
                case .failure:
                    continuation.resume(throwing: EngineError.modelLoadFailed)
                }
            }
        }
    }

    enum EngineError: Error {
        case modelLoadFailed
    }
}
