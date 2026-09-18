import CoreGraphics
import CoreImage
import CoreVideo
import Foundation
import UltralyticsYOLO

/// Uses the same bundled-model loading path as the upstream Ultralytics iOS package.
/// ADASPipeline serializes inference and keeps only the latest frame.
final class UltralyticsDetectionEngine: @unchecked Sendable {
    private var model: YOLO?
    private var loadingModel: YOLO?
    private var loadingTask: Task<YOLO, Error>?
    private var busy = false
    private var pendingPixelBuffer: CVPixelBuffer?
    private(set) var replacedFrames: UInt64 = 0
    private(set) var latestDetections: [ADASDetection] = []
    private(set) var inferenceMilliseconds: Double = 0
    var onResult: (([ADASDetection], Double) -> Void)?
    var onError: ((String) -> Void)?

    func submit(pixelBuffer: CVPixelBuffer) {
        if busy {
            if pendingPixelBuffer != nil { replacedFrames &+= 1 }
            pendingPixelBuffer = pixelBuffer
            return
        }
        run(pixelBuffer)
    }

    private func run(_ pixelBuffer: CVPixelBuffer) {
        busy = true
        Task { [weak self] in
            guard let self else { return }
            let start = ProcessInfo.processInfo.systemUptime
            do {
                let detections = try await self.infer(pixelBuffer: pixelBuffer)
                let ms = (ProcessInfo.processInfo.systemUptime - start) * 1000
                self.latestDetections = detections
                self.inferenceMilliseconds = ms
                self.onResult?(detections, ms)
            } catch {
                self.onError?(error.localizedDescription)
            }
            self.busy = false
            if let next = self.pendingPixelBuffer {
                self.pendingPixelBuffer = nil
                self.run(next)
            }
        }
    }

    func infer(pixelBuffer: CVPixelBuffer) async throws -> [ADASDetection] {
        let yolo = try await loadedModel()
        let result = yolo(CIImage(cvPixelBuffer: pixelBuffer).oriented(.down))
        let detections = result.boxes.map { box in
            ADASDetection(id: UUID(), label: box.cls, confidence: box.conf, boundingBox: box.xywhn)
        }
        return detections.filter { $0.confidence >= 0.35 }
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


struct ADASDetection: Sendable, Identifiable {
    let id: UUID
    let label: String
    let confidence: Float
    let boundingBox: CGRect
}
