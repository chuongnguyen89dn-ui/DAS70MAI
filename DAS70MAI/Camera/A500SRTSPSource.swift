import Foundation
import CoreVideo

/// A500S source using the full xADAS native RTSP/RTP transport and DAS VideoToolbox output.
final class A500SRTSPSource: @unchecked Sendable {
    enum State: Sendable, Equatable { case idle, connecting, streaming, failed(String) }
    var onStateChanged: (@Sendable (State) -> Void)?
    var onPixelBuffer: (@Sendable (CVPixelBuffer) -> Void)?

    private let native = A500SNativeRTSPClient()
    private let decoder = H264VideoToolboxDecoder()
    private var stopped = true
    private var gotFrame = false

    init() {
        native.onStatus = { [weak self] status in
            guard let self else { return }
            if status.contains("ERROR") || status.contains("FAILED") || status.contains("STALLED") || status.contains("NO RTP") || status.contains("INVALID") {
                self.onStateChanged?(.failed(status))
            } else {
                self.onStateChanged?(.connecting)
            }
        }
        native.onAccessUnit = { [weak self] nals in self?.decoder.decode(nalus: nals) }
        decoder.onPixelBuffer = { [weak self] pixelBuffer in
            guard let self, !self.stopped else { return }
            self.native.noteDecodedFrame()
            if !self.gotFrame { self.gotFrame = true; self.onStateChanged?(.streaming) }
            self.onPixelBuffer?(pixelBuffer)
        }
    }

    func start() {
        stop()
        stopped = false
        gotFrame = false
        onStateChanged?(.connecting)
        native.start()
    }

    func stop() {
        stopped = true
        gotFrame = false
        native.stop()
        decoder.reset()
        onStateChanged?(.idle)
    }
}
