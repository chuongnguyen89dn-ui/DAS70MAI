import Foundation
import UIKit
import VLCKit

/// A500S: xADAS-style native RTSP negotiation first, then VLC only as the decoder fallback.
final class A500SRTSPSource: NSObject, @unchecked Sendable, VLCMediaPlayerDelegate {
    enum State: Sendable, Equatable { case idle, connecting, streaming, failed(String) }
    var onStateChanged: (@Sendable (State) -> Void)?
    var onPixelBuffer: (@Sendable (CVPixelBuffer) -> Void)?
    private let player = VLCMediaPlayer()
    private let native = A500SNativeRTSPClient()
    private var drawable: UIView?
    private var snapshotTimer: Timer?
    private var watchdog: Timer?
    private var snapshotPath: String?
    private var inFlight = false
    private var processing = false
    private var stopped = true
    private var lastFrame = 0.0
    private var counter: UInt64 = 0
    private let frameQueue = DispatchQueue(label: "das70mai.a500s.frame", qos: .userInitiated)

    override init() {
        super.init()
        player.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(snapshotTaken(_:)), name: VLCMediaPlayer.snapshotTakenNotification, object: player)
        native.onStatus = { [weak self] status in self?.onStateChanged?(.failed(status)) }
        native.onNegotiated = { [weak self] url in DispatchQueue.main.async { self?.startVLC(url) } }
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func start() { stop(); stopped = false; onStateChanged?(.connecting); native.start() }
    func stop() {
        stopped = true
        native.stop()
        stopLoops()
        player.stop()
        DispatchQueue.main.async { [weak self] in self?.player.drawable = nil }
        onStateChanged?(.idle)
    }

    @MainActor private func startVLC(_ negotiated: URL) {
        guard !stopped else { return }
        stopLoops()
        player.stop()
        onStateChanged?(.connecting)
        guard let media = VLCMedia(url: negotiated) else { onStateChanged?(.failed("VLC media invalid")); return }
        [":network-caching=180", ":live-caching=180", ":clock-jitter=0", ":clock-synchro=0", ":drop-late-frames", ":skip-frames"].forEach { media.addOption($0) }
        player.media = media
        if drawable == nil {
            let view = UIView(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
            view.backgroundColor = .black
            drawable = view
        }
        player.drawable = drawable
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) { [weak self] in
            guard let self, !self.stopped else { return }
            self.player.play()
        }
    }

    func mediaPlayerStateChanged(_ state: VLCMediaPlayerState) {
        switch state {
        case .opening: onStateChanged?(.connecting)
        case .playing: lastFrame = ProcessInfo.processInfo.systemUptime; startLoops()
        case .error: onStateChanged?(.failed("VLC decoder error after native PLAY"))
        case .stopped: if !stopped { onStateChanged?(.failed("VLC stopped after native PLAY")) }
        default: break
        }
    }

    private func startLoops() {
        guard snapshotTimer == nil else { return }
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in self?.snap() }
        watchdog = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, !self.processing, ProcessInfo.processInfo.systemUptime - self.lastFrame > 2.4 else { return }
            self.onStateChanged?(.failed("native PLAY OK but no decoded frame"))
        }
        snap()
    }

    private func stopLoops() {
        snapshotTimer?.invalidate(); snapshotTimer = nil
        watchdog?.invalidate(); watchdog = nil
        inFlight = false; processing = false
        if let path = snapshotPath { try? FileManager.default.removeItem(atPath: path) }
        snapshotPath = nil
    }

    private func snap() {
        guard player.state == .playing, !inFlight, !processing else { return }
        counter &+= 1
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("a500s-native-\(counter % 2).png").path
        try? FileManager.default.removeItem(atPath: path)
        snapshotPath = path; inFlight = true
        player.saveVideoSnapshot(at: path, withWidth: 960, andHeight: 540)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in self?.inFlight = false }
    }

    @objc private func snapshotTaken(_ notification: Notification) {
        guard let path = snapshotPath else { inFlight = false; return }
        snapshotPath = nil; inFlight = false; processing = true
        lastFrame = ProcessInfo.processInfo.systemUptime
        onStateChanged?(.streaming)
        frameQueue.async { [weak self] in
            guard let self, let image = UIImage(contentsOfFile: path), let cg = image.cgImage, let buffer = Self.pixelBuffer(cg) else {
                try? FileManager.default.removeItem(atPath: path)
                DispatchQueue.main.async { self?.processing = false }
                return
            }
            try? FileManager.default.removeItem(atPath: path)
            self.onPixelBuffer?(buffer)
            DispatchQueue.main.async { self.processing = false }
        }
    }

    private static func pixelBuffer(_ image: CGImage) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer) == kCVReturnSuccess, let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), let cs = CGColorSpace(name: CGColorSpace.sRGB), let ctx = CGContext(data: base, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: cs, bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}
