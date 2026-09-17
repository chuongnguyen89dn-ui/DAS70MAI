import CoreVideo
import Foundation

enum VideoSourceKind: String, Sendable {
    case a500s
    case iPhoneRearCamera
}

struct VideoFrame: @unchecked Sendable {
    let pixelBuffer: CVPixelBuffer
    let source: VideoSourceKind
    let receivedAt: ContinuousClock.Instant
}

protocol VideoSource: AnyObject {
    var kind: VideoSourceKind { get }
    var onFrame: (@Sendable (VideoFrame) -> Void)? { get set }
    var onAvailabilityChanged: (@Sendable (Bool) -> Void)? { get set }
    func start()
    func stop()
}
