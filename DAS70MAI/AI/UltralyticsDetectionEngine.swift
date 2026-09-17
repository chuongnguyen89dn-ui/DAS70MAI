import CoreImage
import CoreVideo
import Foundation
import UltralyticsYOLO

final class UltralyticsDetectionEngine: @unchecked Sendable, ADASInferenceEngine {
    private let lock = NSLock()
    private var model: YOLO?
    private var loadingTask: Task<YOLO, Error>?

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
        lock.lock()
        if let model, model.isLoaded {
            lock.unlock()
            return model
        }
        if let loadingTask {
            lock.unlock()
            return try await loadingTask.value
        }

        let task = Task<YOLO, Error> {
            try await withCheckedThrowingContinuation { continuation in
                let remote = URL(string: "https://github.com/ultralytics/yolo-ios-app/releases/download/v8.3.0/yolo26n.mlpackage.zip")!
                _ = YOLO(url: remote, task: .detect, useGpu: true, numItemsThreshold: 30) { result in
                    switch result {
                    case .success(let loaded):
                        loaded.setConfidenceThreshold(0.35)
                        continuation.resume(returning: loaded)
                    case .failure:
                        continuation.resume(throwing: EngineError.modelLoadFailed)
                    }
                }
            }
        }
        loadingTask = task
        lock.unlock()

        do {
            let loaded = try await task.value
            lock.lock()
            model = loaded
            loadingTask = nil
            lock.unlock()
            return loaded
        } catch {
            lock.lock()
            loadingTask = nil
            lock.unlock()
            throw error
        }
    }

    enum EngineError: Error { case modelLoadFailed }
}
