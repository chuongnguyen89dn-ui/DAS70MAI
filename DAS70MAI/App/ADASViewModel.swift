import Foundation
import SwiftUI

@MainActor
final class ADASViewModel: ObservableObject {
    @Published var detections: [ADASDetection] = []
    @Published var risk: ForwardRisk = .init(level: .clear, object: nil)
    @Published var inferenceActive = false

    let rearCamera = RearCameraSource()
    private let engine = UltralyticsDetectionEngine()
    private lazy var pipeline = ADASPipeline(engine: engine)
    private var warningDebouncer = WarningDebouncer()

    init() {
        rearCamera.onFrame = { [weak self] frame in
            guard let self else { return }
            Task { await self.pipeline.submit(frame) }
        }
        Task {
            await pipeline.setResultHandler { [weak self] result in
                let relevant = RoadObjectFilter.relevant(result.detections)
                Task { @MainActor in
                    guard let self else { return }
                    detections = relevant
                    let rawRisk = ForwardRiskEvaluator.evaluate(relevant)
                    let stableLevel = warningDebouncer.update(with: rawRisk)
                    risk = ForwardRisk(level: stableLevel, object: rawRisk.object)
                    inferenceActive = true
                }
            }
        }
    }

    func startRearCamera() { rearCamera.start() }
    func stopRearCamera() {
        rearCamera.stop()
        detections = []
        warningDebouncer.reset()
        risk = .init(level: .clear, object: nil)
        inferenceActive = false
    }
}
