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

    init() {
        rearCamera.onFrame = { [weak self] frame in
            guard let self else { return }
            Task { await self.pipeline.submit(frame) }
        }
        Task {
            await pipeline.setResultHandler { [weak self] result in
                let relevant = RoadObjectFilter.relevant(result.detections)
                Task { @MainActor in
                    self?.detections = relevant
                    self?.risk = ForwardRiskEvaluator.evaluate(relevant)
                    self?.inferenceActive = true
                }
            }
        }
    }

    func startRearCamera() { rearCamera.start() }
    func stopRearCamera() {
        rearCamera.stop()
        detections = []
        risk = .init(level: .clear, object: nil)
        inferenceActive = false
    }
}
