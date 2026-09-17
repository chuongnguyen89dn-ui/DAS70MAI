import CoreVideo
import Foundation

struct ADASDetection: Sendable, Identifiable {
    let id: UUID
    let label: String
    let confidence: Float
    /// Normalized Vision/Core ML coordinates (0...1).
    let boundingBox: CGRect
}

struct ADASFrameResult: Sendable {
    let source: VideoSourceKind
    let detections: [ADASDetection]
    let processedAt: ContinuousClock.Instant
}

protocol ADASInferenceEngine: Sendable {
    func infer(pixelBuffer: CVPixelBuffer, source: VideoSourceKind) async throws -> ADASFrameResult
}

/// Common ingestion point for both manually selected camera sources.
actor ADASPipeline {
    private let frames = LatestFrameStore()
    private let engine: ADASInferenceEngine
    private var workerRunning = false
    private var onResult: (@Sendable (ADASFrameResult) -> Void)?

    init(engine: ADASInferenceEngine) {
        self.engine = engine
    }

    func setResultHandler(_ handler: @escaping @Sendable (ADASFrameResult) -> Void) {
        onResult = handler
    }

    func submit(_ frame: VideoFrame) async {
        await frames.push(frame)
        guard !workerRunning else { return }
        workerRunning = true
        Task { await drainLatestFrames() }
    }

    private func drainLatestFrames() async {
        while let frame = await frames.takeLatest() {
            do {
                let result = try await engine.infer(pixelBuffer: frame.pixelBuffer, source: frame.source)
                onResult?(result)
            } catch {
                // Inference errors are isolated from camera capture; next frame may still succeed.
            }
        }
        workerRunning = false
    }
}
