import CoreVideo
import Foundation

struct ADASDetection: Sendable, Identifiable {
    let id: UUID
    let label: String
    let confidence: Float
    /// Normalized Ultralytics display coordinates (0...1, top-left origin).
    let boundingBox: CGRect
}

struct ADASFrameResult: Sendable {
    let source: VideoSourceKind
    let detections: [ADASDetection]
    let processedAt: ContinuousClock.Instant
}

struct ADASRuntimeMetrics: Sendable {
    let inferenceMilliseconds: Double
    let frameAgeMilliseconds: Double
    let replacedFrames: UInt64
}

protocol ADASInferenceEngine: Sendable {
    func infer(pixelBuffer: CVPixelBuffer, source: VideoSourceKind) async throws -> ADASFrameResult
}

/// Common ingestion point for both manually selected camera sources.
actor ADASPipeline {
    private let frames = LatestFrameStore()
    private let engine: ADASInferenceEngine
    private var workerRunning = false
    private var onResult: (@Sendable (ADASFrameResult, ADASRuntimeMetrics) -> Void)?
    private var onError: (@Sendable (String) -> Void)?

    init(engine: ADASInferenceEngine) { self.engine = engine }

    func setResultHandler(_ handler: @escaping @Sendable (ADASFrameResult, ADASRuntimeMetrics) -> Void) { onResult = handler }
    func setErrorHandler(_ handler: @escaping @Sendable (String) -> Void) { onError = handler }

    func submit(_ frame: VideoFrame) async {
        await frames.push(frame)
        guard !workerRunning else { return }
        workerRunning = true
        Task { await drainLatestFrames() }
    }

    private func drainLatestFrames() async {
        let clock = ContinuousClock()
        while let frame = await frames.takeLatest() {
            do {
                let inferenceStart = clock.now
                let result = try await engine.infer(pixelBuffer: frame.pixelBuffer, source: frame.source)
                let processedAt = clock.now
                let metrics = ADASRuntimeMetrics(
                    inferenceMilliseconds: Self.milliseconds(inferenceStart.duration(to: processedAt)),
                    frameAgeMilliseconds: Self.milliseconds(frame.receivedAt.duration(to: processedAt)),
                    replacedFrames: await frames.replacedFrames
                )
                onResult?(result, metrics)
            } catch {
                onError?(error.localizedDescription)
            }
        }
        workerRunning = false
    }

    private static func milliseconds(_ duration: Duration) -> Double {
        let components = duration.components
        return Double(components.seconds) * 1_000 + Double(components.attoseconds) / 1_000_000_000_000_000
    }
}
