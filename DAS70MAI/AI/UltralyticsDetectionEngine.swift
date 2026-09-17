import CoreImage
import CoreVideo
import Foundation
import UltralyticsYOLO

/// Uses the same bundled-model loading path as the upstream Ultralytics iOS package.
/// ADASPipeline serializes inference and keeps only the latest frame.
final class UltralyticsDetectionEngine: @unchecked Sendable, ADASInferenceEngine {
    private var model: YOLO?
    private var loadingModel: YOLO?
    private var loadingTask: Task<YOLO, Error>?

    func infer(pixelBuffer: CVPixelBuffer, source: VideoSourceKind) async throws -> ADASFrameResult {
        let yolo = try await loadedModel()
        let result = yolo(CIImage(cvPixelBuffer: pixelBuffer))
        let detections = result.boxes.map { box in
            ADASDetection(id: UUID(), label: box.cls, confidence: box.conf, boundingBox: box.xywhn)
        }
        return ADASFrameResult(source: source, detections: RoadObjectFilter.relevant(detections), processedAt: .now)
    }

    private func loadedModel() async throws -> YOLO {
        if let model, model.isLoaded { return model }
        if let loadingTask { return try await loadingTask.value }

        let task = Task<YOLO, Error> {
            try await withCheckedThrowingContinuation { continuation in
                // Keep the loader alive. Upstream model loading is asynchronous and
                // uses weak self internally, so discarding this instance can leave
                // the continuation waiting forever on a physical device.
                let candidate = YOLO("yolo26n", task: .detect, useGpu: true, numItemsThreshold: 30) { result in
                    switch result {
                    case .success(let loaded):
                        loaded.setConfidenceThreshold(0.35)
                        continuation.resume(returning: loaded)
                    case .failure(let error):
                        continuation.resume(throwing: EngineError.modelLoadFailed(String(describing: error)))
                    }
                }
                self.loadingModel = candidate
            }
        }
        loadingTask = task
        do {
            let loaded = try await task.value
            model = loaded
            loadingModel = nil
            loadingTask = nil
            return loaded
        } catch {
            loadingModel = nil
            loadingTask = nil
            throw error
        }
    }

    enum EngineError: Error, LocalizedError {
        case modelLoadFailed(String)
        var errorDescription: String? {
            switch self { case .modelLoadFailed(let detail): return "Bundled YOLO model failed: \(detail)" }
        }
    }
}
