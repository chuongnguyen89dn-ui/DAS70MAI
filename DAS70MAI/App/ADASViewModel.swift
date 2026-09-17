import CoreImage
import CoreVideo
import Foundation
import SwiftUI

@MainActor
final class ADASViewModel: ObservableObject {
    @Published var detections: [ADASDetection] = []
    @Published var laneSegments: [LaneSegment] = []
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
    private let laneDetector = LaneDetector()
    private lazy var pipeline = ADASPipeline(engine: engine)
    private var warningDebouncer = WarningDebouncer()
    private let warningFeedback = WarningFeedbackController()
    private var laneFrameCounter = 0

    init() {
        rearCamera.onFrame = { [weak self] frame in
            guard let self else { return }
            Task { await self.pipeline.submit(frame) }
            self.detectLanesIfNeeded(frame.pixelBuffer)
        }
        a500s.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in self?.a500sState = state }
        }
        a500s.onH264AccessUnit = { [weak self] nalus, _, _ in self?.a500sDecoder.decode(nalus: nalus) }
        a500sDecoder.onPixelBuffer = { [weak self] pixelBuffer in
            guard let self else { return }
            let frame = VideoFrame(pixelBuffer: pixelBuffer, source: .a500s, receivedAt: .now)
            Task { await self.pipeline.submit(frame) }
            self.detectLanesIfNeeded(pixelBuffer)
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.cacheIntermediates: false])
            if let preview = context.createCGImage(image, from: image.extent) {
                Task { @MainActor [weak self] in self?.a500sFrame = preview }
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
                    self.warningFeedback.update(level: stableLevel)
                    self.inferenceMilliseconds = metrics.inferenceMilliseconds
                    self.frameAgeMilliseconds = metrics.frameAgeMilliseconds
                    self.replacedFrames = metrics.replacedFrames
                    self.inferenceActive = true
                }
            }
        }
    }

    nonisolated private func detectLanesIfNeeded(_ pixelBuffer: CVPixelBuffer) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.laneFrameCounter += 1
            guard self.laneFrameCounter % 5 == 0 else { return }
            let detector = self.laneDetector
            Task.detached(priority: .utility) { [weak self] in
                let segments = detector.detect(pixelBuffer: pixelBuffer)
                await MainActor.run { self?.laneSegments = segments }
            }
        }
    }

    func startRearCamera() { stopA500S(); rearCamera.start() }
    func startA500S() { rearCamera.stop(); resetRuntime(); a500s.start() }
    func stopRearCamera() { rearCamera.stop(); resetRuntime() }
    func stopA500S() { a500s.stop(); a500sDecoder.reset(); a500sFrame = nil; resetRuntime() }

    private func resetRuntime() {
        detections = []
        laneSegments = []
        laneFrameCounter = 0
        warningDebouncer.reset()
        warningFeedback.reset()
        risk = .init(level: .clear, object: nil)
        inferenceActive = false
        inferenceMilliseconds = 0
        frameAgeMilliseconds = 0
        replacedFrames = 0
    }
}
