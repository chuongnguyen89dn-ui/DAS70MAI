import AVFoundation
import Combine
import CoreMedia
import CoreVideo
import CoreImage
import UltralyticsYOLO

final class FrameProcessor: ObservableObject {
    @Published private(set) var processedFrames: UInt64 = 0
    @Published private(set) var frameWidth: Int = 0
    @Published private(set) var frameHeight: Int = 0
    @Published private(set) var pipelineStatus = "FRAME PIPELINE READY"
    @Published private(set) var detections: [VehicleDetection] = []
    @Published private(set) var inferenceMS: Double = 0
    @Published private(set) var detectorStatus = "MODEL NOT LOADED"
    @Published private(set) var leadDistanceMeters: Double?
    @Published private(set) var leadDistanceState = LeadDistanceState(distanceMeters: nil, closingSpeedMetersPerSecond: nil, risk: .unavailable)
    @Published private(set) var laneDetection: LaneDetection?
    @Published private(set) var laneDepartureState: LaneDepartureState = .unavailable
    @Published private(set) var laneStatus = "LANE MODEL LOADING"
    @Published private(set) var trafficSignState = TrafficSignState()
    @Published private(set) var trafficSignStatus = "SIGN AI PAUSED • PERFORMANCE MODE"
    @Published private(set) var dasDetections: [ADASDetection] = []
    @Published private(set) var dasInferenceMS: Double = 0
    @Published private(set) var dasRisk = ForwardRisk(level: .clear, object: nil)
    @Published private(set) var dasLaneDetection: LaneDetection?
    @Published private(set) var dasReplacedFrames: UInt64 = 0
    @Published private(set) var dasFrameAgeMS: Double = 0
    @Published private(set) var dasInferenceError: String?
    @Published private(set) var dasPipelineAgeMS: Double = 0
    @Published private(set) var dasInputDroppedFrames: UInt64 = 0
    private var dasLastFrameAt = ProcessInfo.processInfo.systemUptime
    private var dasLaneFrameCounter = 0
    private let dasLaneDetector = LaneDetector()
    private var dasWarningDebouncer = WarningDebouncer()
    private let dasWarningFeedback = WarningFeedbackController()

    var horizontalFieldOfViewDegrees: Double = 0
    var effectiveFocalPixelsAt1920: Double?
    var vehicleSpeedKPH: Double = 0

    private var totalFrames: UInt64 = 0
    private var lastPublishedAt = ProcessInfo.processInfo.systemUptime
    private var inferenceFrameCounter = 0
    private var laneFrameCounter = 1
    private var lastVehicleSeenAt: TimeInterval = 0
    private var lastLaneSeenAt: TimeInterval = 0
    // Preserve Ivy detector for the existing HUD while DAS YOLO is transplanted in parallel.
    private let detector: VehicleDetector?
    private let dasYOLO = UltralyticsDetectionEngine()
    private let distanceEstimator = DistanceEstimator()
    private let leadDistanceTracker = LeadDistanceTracker()
    private let laneDetector: LaneAIDetector?
    private let laneDepartureMonitor = LaneDepartureMonitor()
    private var latestLaneDetection: LaneDetection?

    init() {
        do { detector = try VehicleDetector(); detectorStatus = "VEHICLE MODEL READY" }
        catch { detector = nil; detectorStatus = error.localizedDescription }
        do { laneDetector = try LaneAIDetector(); laneStatus = "UFLD V2 LANE MODEL READY" }
        catch { laneDetector = nil; laneStatus = error.localizedDescription }
        dasYOLO.onError = { [weak self] message in
            DispatchQueue.main.async { self?.dasInferenceError = message }
        }
        dasYOLO.onResult = { [weak self] detections, ms in
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                self.dasDetections = detections; self.dasInferenceMS = ms
                self.dasReplacedFrames = self.dasYOLO.replacedFrames
                self.dasFrameAgeMS = max(0, (ProcessInfo.processInfo.systemUptime - self.dasLastFrameAt) * 1000)
                self.dasPipelineAgeMS = self.dasFrameAgeMS
                self.dasInferenceError = nil
                let rawRisk = ForwardRiskEvaluator.evaluate(detections)
                let stable = self.dasWarningDebouncer.update(with: rawRisk)
                self.dasRisk = ForwardRisk(level: stable, object: rawRisk.object)
                self.dasWarningFeedback.update(level: stable)
            }
        }
    }

    func noteDASInputDrop() { DispatchQueue.main.async { [weak self] in self?.dasInputDroppedFrames &+= 1 } }

    @MainActor func setDASSoundEnabled(_ enabled: Bool) { dasWarningFeedback.soundEnabled = enabled }
    @MainActor func setDASVibrationEnabled(_ enabled: Bool) { dasWarningFeedback.vibrationEnabled = enabled }

    /// Ivy MAX uses speed-aware inference while retaining thermal protection.
    /// Highway: maximum lead/lane reaction rate.
    /// City: balanced load.
    /// Standstill: vehicle remains responsive for lead-departure alert while lane is relaxed.
    private var adaptiveStride: (vehicle: Int, lane: Int, label: String) {
        switch ProcessInfo.processInfo.thermalState {
        case .critical:
            return (6, 8, "THERMAL SAFE")
        case .serious:
            return (4, 6, "THERMAL SAFE")
        case .fair:
            if vehicleSpeedKPH >= 60 { return (2, 3, "MAX HIGHWAY") }
            return vehicleSpeedKPH <= 3 ? (3, 6, "MAX STOP") : (3, 4, "MAX CITY")
        case .nominal:
            if vehicleSpeedKPH >= 60 { return (1, 2, "MAX HIGHWAY") }
            if vehicleSpeedKPH <= 3 { return (2, 5, "MAX STOP") }
            return (2, 3, "MAX CITY")
        @unknown default:
            return (3, 4, "MAX AUTO")
        }
    }


    func process(sampleBuffer: CMSampleBuffer) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let sampleTime = CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sampleBuffer))
        process(pixelBuffer: pixelBuffer, timestamp: sampleTime.isFinite ? sampleTime : ProcessInfo.processInfo.systemUptime)
    }

    func process(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval = ProcessInfo.processInfo.systemUptime) {
        totalFrames &+= 1
        // DAS YOLO runs off the decoded pixel buffer only; camera/RTSP/render lifecycle is untouched.
        dasLastFrameAt = ProcessInfo.processInfo.systemUptime
        dasYOLO.submit(pixelBuffer: pixelBuffer)
        dasLaneFrameCounter += 1
        if dasLaneFrameCounter % 5 == 0 {
            let detector = dasLaneDetector
            DispatchQueue.global(qos: .utility).async { [weak self] in
                let detection = detector.detect(pixelBuffer: pixelBuffer)
                DispatchQueue.main.async { self?.dasLaneDetection = detection }
            }
        }
        inferenceFrameCounter &+= 1
        laneFrameCounter &+= 1
        let stride = adaptiveStride
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        var newDetections: [VehicleDetection]?
        var newInferenceMS: Double?
        var newLeadState: LeadDistanceState?
        var newLaneDetection: LaneDetection?
        var laneWasEvaluated = false
        var newLaneState: LaneDepartureState?

        if inferenceFrameCounter >= stride.vehicle, let detector {
            inferenceFrameCounter = 0
            do {
                let result = try detector.detect(pixelBuffer: pixelBuffer)
                newDetections = result.detections.map { $0.markingLead(false) }
                newInferenceMS = result.inferenceMS
            } catch {
                let message = error.localizedDescription
                DispatchQueue.main.async { [weak self] in self?.detectorStatus = "MODEL ERROR: \(message)" }
            }
        }

        if laneFrameCounter >= stride.lane, let laneDetector {
            laneFrameCounter = 0
            laneWasEvaluated = true
            do {
                let lane = try laneDetector.detect(pixelBuffer: pixelBuffer)
                if let lane {
                    lastLaneSeenAt = ProcessInfo.processInfo.systemUptime
                    latestLaneDetection = lane
                    newLaneDetection = lane
                    newLaneState = laneDepartureMonitor.update(with: lane)
                } else if ProcessInfo.processInfo.systemUptime - lastLaneSeenAt > 0.7 {
                    latestLaneDetection = nil
                    newLaneDetection = nil
                    newLaneState = laneDepartureMonitor.update(with: nil)
                } else {
                    laneWasEvaluated = false
                }
            } catch {
                newLaneDetection = nil
                newLaneState = laneDepartureMonitor.update(with: nil)
            }
        }

        if var measured = newDetections {
            if let lane = latestLaneDetection,
               let leadIndex = leadVehicleIndex(in: measured, lane: lane) {
                let leadBox = measured[leadIndex].boundingBox
                let rawDistance = distanceEstimator.estimate(
                    for: leadBox,
                    frameWidth: width,
                    frameHeight: height,
                    horizontalFieldOfViewDegrees: horizontalFieldOfViewDegrees,
                    effectiveFocalPixelsAt1920: effectiveFocalPixelsAt1920
                )
                let tracked = leadDistanceTracker.update(rawDistance: rawDistance, leadBox: leadBox, timestamp: timestamp)
                measured[leadIndex] = measured[leadIndex].markingLead(true).withDistance(tracked.distanceMeters)
                newLeadState = tracked
                lastVehicleSeenAt = ProcessInfo.processInfo.systemUptime
            } else if ProcessInfo.processInfo.systemUptime - lastVehicleSeenAt > 0.55 {
                leadDistanceTracker.reset()
                newLeadState = LeadDistanceState(distanceMeters: nil, closingSpeedMetersPerSecond: nil, risk: .unavailable)
            }
            measured = measured.filter { $0.isLead }
            newDetections = measured
        }

        let now = ProcessInfo.processInfo.systemUptime
        let shouldPublishMetrics = now - lastPublishedAt >= 0.5
        guard shouldPublishMetrics || newDetections != nil || laneWasEvaluated else { return }
        if shouldPublishMetrics { lastPublishedAt = now }
        let count = totalFrames
        let modeLabel = stride.label

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            if shouldPublishMetrics {
                self.frameWidth = width
                self.frameHeight = height
                self.processedFrames = count
                self.pipelineStatus = "IVY AI • \(modeLabel)"
            }
            if let newDetections {
                self.detections = newDetections
                if let newLeadState {
                    self.leadDistanceState = newLeadState
                    self.leadDistanceMeters = newLeadState.distanceMeters
                }
                self.detectorStatus = newDetections.isEmpty ? "LEAD SEARCH • IVY CORRIDOR" : "LEAD LOCK • IVY CORRIDOR"
            }
            if let newInferenceMS { self.inferenceMS = newInferenceMS }
            if laneWasEvaluated {
                self.laneDetection = newLaneDetection
                if let newLaneState { self.laneDepartureState = newLaneState }
                self.laneStatus = newLaneDetection == nil ? "LANE SEARCHING" : "LANE ACTIVE • EGO LOCK"
            }
        }
    }

    private func leadVehicleIndex(in detections: [VehicleDetection], lane: LaneDetection) -> Int? {
        let candidates = detections.indices.filter { index in
            let box = detections[index].boundingBox
            let contactY = 1.0 - Double(box.minY)
            let contactX = Double(box.midX)
            guard let leftX = fittedLaneX(lane.leftPoints, at: contactY),
                  let rightX = fittedLaneX(lane.rightPoints, at: contactY),
                  rightX > leftX,
                  contactX >= leftX,
                  contactX <= rightX else { return false }
            guard contactY >= 0.34 && contactY <= 0.96 else { return false }
            let t = max(0.0, min(1.0, (contactY - 0.48) / (0.94 - 0.48)))
            let halfWidth = 0.075 + (0.235 - 0.075) * t
            return abs(contactX - 0.50) <= halfWidth
        }
        return candidates.max { lhs, rhs in
            let a = detections[lhs].boundingBox
            let b = detections[rhs].boundingBox
            return (1.0 - Double(a.minY)) + Double(a.width * a.height) < (1.0 - Double(b.minY)) + Double(b.width * b.height)
        }
    }

    private func fittedLaneX(_ points: [CGPoint], at y: Double) -> Double? {
        guard points.count >= 6 else { return nil }
        let count = Double(points.count)
        let sumY = points.reduce(0.0) { $0 + Double($1.y) }
        let sumX = points.reduce(0.0) { $0 + Double($1.x) }
        let sumYY = points.reduce(0.0) { $0 + Double($1.y * $1.y) }
        let sumYX = points.reduce(0.0) { $0 + Double($1.y * $1.x) }
        let denominator = count * sumYY - sumY * sumY
        guard abs(denominator) > 0.000_001 else { return nil }
        let slope = (count * sumYX - sumY * sumX) / denominator
        let intercept = (sumX - slope * sumY) / count
        let x = slope * y + intercept
        return x.isFinite ? x : nil
    }
}
