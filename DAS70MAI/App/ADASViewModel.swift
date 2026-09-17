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
    @Published var inferenceError: String?
    @Published var inferenceMilliseconds: Double = 0
    @Published var frameAgeMilliseconds: Double = 0
    @Published var replacedFrames: UInt64 = 0
    @Published var a500sState: A500SRTSPSource.State = .idle
    @Published var a500sFrame: CGImage?
    @Published var soundEnabled = true { didSet { warningFeedback.soundEnabled = soundEnabled } }
    @Published var vibrationEnabled = true { didSet { warningFeedback.vibrationEnabled = vibrationEnabled } }

    let rearCamera = RearCameraSource()
    private let a500s = A500SRTSPSource()
    private let engine = UltralyticsDetectionEngine()
    private let laneDetector = LaneDetector()
    private lazy var pipeline = ADASPipeline(engine: engine)
    private var warningDebouncer = WarningDebouncer()
    private let warningFeedback = WarningFeedbackController()
    private var laneFrameCounter = 0
    private var activeSource: VideoSourceKind?
    private var sourceGeneration: UInt64 = 0

    init() {
        rearCamera.onFrame = { [weak self] frame in
            guard let self else { return }
            Task { await self.pipeline.submit(frame) }
            self.detectLanesIfNeeded(frame, source: .iPhoneRearCamera)
        }
        a500s.onStateChanged = { [weak self] state in
            Task { @MainActor [weak self] in self?.a500sState = state }
        }
        a500s.onPixelBuffer = { [weak self] pixelBuffer in
            guard let self else { return }
            let frame = VideoFrame(pixelBuffer: pixelBuffer, source: .a500s, receivedAt: .now)
            Task { await self.pipeline.submit(frame) }
            self.detectLanesIfNeeded(frame, source: .a500s)
            let image = CIImage(cvPixelBuffer: pixelBuffer)
            let context = CIContext(options: [.cacheIntermediates: false])
            if let preview = context.createCGImage(image, from: image.extent) {
                Task { @MainActor [weak self] in
                    guard let self, self.activeSource == .a500s else { return }
                    self.a500sFrame = preview
                }
            }
        }
        Task {
            await pipeline.setResultHandler { [weak self] result, metrics in
                let relevant = RoadObjectFilter.relevant(result.detections)
                Task { @MainActor [weak self] in
                    guard let self, self.activeSource == result.source else { return }
                    self.detections = relevant
                    let rawRisk = ForwardRiskEvaluator.evaluate(relevant)
                    let stableLevel = self.warningDebouncer.update(with: rawRisk)
                    self.risk = ForwardRisk(level: stableLevel, object: rawRisk.object)
                    self.warningFeedback.update(level: stableLevel)
                    self.inferenceMilliseconds = metrics.inferenceMilliseconds
                    self.frameAgeMilliseconds = metrics.frameAgeMilliseconds
                    self.replacedFrames = metrics.replacedFrames
                    self.inferenceError = nil
                    self.inferenceActive = true
                }
            }
            await pipeline.setErrorHandler { [weak self] message in
                Task { @MainActor [weak self] in
                    self?.inferenceActive = false
                    self?.inferenceError = message
                }
            }
        }
    }

    private func detectLanesIfNeeded(_ frame: VideoFrame, source: VideoSourceKind) {
        guard activeSource == source else { return }
        laneFrameCounter += 1
        guard laneFrameCounter % 5 == 0 else { return }
        let generation = sourceGeneration
        let detector = laneDetector
        Task.detached(priority: .utility) { [frame, detector] in
            let segments = detector.detect(pixelBuffer: frame.pixelBuffer)
            await MainActor.run { [weak self] in
                guard let self, self.activeSource == source, self.sourceGeneration == generation else { return }
                self.laneSegments = segments
            }
        }
    }

    func startRearCamera() { stopA500S(); beginSource(.iPhoneRearCamera); rearCamera.start() }
    func startA500S() { rearCamera.stop(); beginSource(.a500s); a500s.start() }
    func stopRearCamera() { rearCamera.stop(); endSource(.iPhoneRearCamera) }
    func stopA500S() { a500s.stop(); a500sFrame = nil; endSource(.a500s) }

    private func beginSource(_ source: VideoSourceKind) {
        sourceGeneration &+= 1; activeSource = source; resetRuntime()
    }
    private func endSource(_ source: VideoSourceKind) {
        guard activeSource == source else { return }
        sourceGeneration &+= 1; activeSource = nil; resetRuntime()
    }
    private func resetRuntime() {
        detections = []; laneSegments = []; laneFrameCounter = 0
        warningDebouncer.reset(); warningFeedback.reset()
        risk = .init(level: .clear, object: nil)
        inferenceActive = false; inferenceError = nil; inferenceMilliseconds = 0; frameAgeMilliseconds = 0; replacedFrames = 0
    }
}
