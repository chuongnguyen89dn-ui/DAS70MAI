import CoreImage
import CoreVideo
import Foundation
import SwiftUI

@MainActor
final class ADASViewModel: ObservableObject {
    @Published var detections: [ADASDetection] = []
    @Published var risk: ForwardRisk = .init(level: .clear, object: nil)
    @Published var inferenceActive = false
    @Published var inferenceMilliseconds: Double = 0
    @Published var frameAgeMilliseconds: Double = 0
    @Published var replacedFrames: UInt64 = 0
    @Published var a500sState: A500SRTSPSource.State = .idle
    @Published var a500sFrame: CGImage?

    let rearCamera = RearCameraSource()
    private let a500s = A500SRTSPSource()
    private let a500sDecoder = H264VideoToolboxDecoder()
    private let engine = UltralyticsDetectionEngine()
    private lazy var pipeline = ADASPipeline(engine: engine)
    private var warningDebouncer = WarningDebouncer()

    init() {
        rearCamera.onFrame = { [weak self] frame in
            guard let self else { return }
            Task { await self.pipeline.submit(frame) }
        }
        a500s.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in self?.a500sState = state }
        }
        a500s.onH264AccessUnit = { [weak self] nalus, _, _ in
            self?.a500sDecoder.decode(nalus: nalus)
        }
        a500sDecoder.onPixelBuffer = { [weak self] pixelBuffer in
            guard let self else { return }
            let frame = VideoFrame(pixelBuffer: pixelBuffer, source: .a500s, receivedAt: .now)
            Task { await self.pipeline.submit(frame) }

            // Render the preview into an immutable CGImage before crossing to MainActor.
            // CVPixelBuffer is mutable/non-Sendable and Swift 6 correctly rejects sending it
            // from the VideoToolbox decoder callback into the UI actor.
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.cacheIntermediates: false])
            if let preview = context.createCGImage(image, from: image.extent) {
                Task { @MainActor [weak self] in
                    self?.a500sFrame = preview
                }
            }
        }
        Task {
            await pipeline.setResultHandler { [weak self] result, metrics in
                let relevant = RoadObjectFilter.relevant(result.detections)
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.detections = relevant
                    let rawRisk = ForwardRiskEvaluator.evaluate(relevant)
                    let stableLevel = self.warningDebouncer.update(with: rawRisk)
                    self.risk = ForwardRisk(level: stableLevel, object: rawRisk.object)
                    self.inferenceMilliseconds = metrics.inferenceMilliseconds
                    self.frameAgeMilliseconds = metrics.frameAgeMilliseconds
                    self.replacedFrames = metrics.replacedFrames
                    self.inferenceActive = true
                }
            }
        }
    }

    func startRearCamera() {
        stopA500S()
        rearCamera.start()
    }

    func startA500S() {
        rearCamera.stop()
        resetRuntime()
        a500s.start()
    }

    func stopRearCamera() {
        rearCamera.stop()
        resetRuntime()
    }

    func stopA500S() {
        a500s.stop()
        a500sDecoder.reset()
        a500sFrame = nil
        resetRuntime()
    }

    private func resetRuntime() {
        detections = []
        warningDebouncer.reset()
        risk = .init(level: .clear, object: nil)
        inferenceActive = false
        inferenceMilliseconds = 0
        frameAgeMilliseconds = 0
        replacedFrames = 0
    }
}
