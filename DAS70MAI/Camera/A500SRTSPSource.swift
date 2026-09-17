import Foundation
import UIKit
import VLCKit

/// A500S transport restored from the proven xADAS SeventyMaiPlayerView VLC path.
/// Fixed stream: rtsp://192.168.0.1/00000000. No automatic source switching.
final class A500SRTSPSource: NSObject, @unchecked Sendable, VLCMediaPlayerDelegate {
    enum State: Sendable, Equatable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    var onStateChanged: (@Sendable (State) -> Void)?
    var onPixelBuffer: (@Sendable (CVPixelBuffer) -> Void)?

    private let player = VLCMediaPlayer()
    // xADAS attaches VLC to a real UIView drawable before playback. The previous
    // DAS70MAI adapter omitted this, so VLC could enter .playing without creating
    // a usable video output for snapshots. Keep a private drawable because preview
    // is rendered from the common CVPixelBuffer pipeline, not directly by VLC.
    private var vlcDrawable: UIView?
    private var snapshotTimer: Timer?
    private var watchdogTimer: Timer?
    private var reconnectWorkItem: DispatchWorkItem?
    private var snapshotInFlight = false
    private var frameProcessing = false
    private var snapshotPath: String?
    private var snapshotCounter: UInt64 = 0
    private var stoppedByOwner = true
    private var lastFrameAt = ProcessInfo.processInfo.systemUptime
    private var consecutiveFailures = 0
    private let frameQueue = DispatchQueue(label: "das70mai.a500s.frame", qos: .userInitiated)
    private let streamURL = "rtsp://192.168.0.1/00000000"

    override init() {
        super.init()
        player.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(snapshotTaken(_:)), name: VLCMediaPlayer.snapshotTakenNotification, object: player)
    }

    deinit { NotificationCenter.default.removeObserver(self) }

    func start() {
        stop()
        stoppedByOwner = false
        consecutiveFailures = 0
        startPlayer()
    }

    private func startPlayer() {
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopSnapshotLoop()
        onStateChanged?(.connecting)
        player.stop()
        guard let url = URL(string: streamURL), let media = VLCMedia(url: url) else {
            onStateChanged?(.failed("invalid A500S RTSP URL"))
            return
        }

        // Match xADAS A500S VLC options exactly.
        media.addOption(":network-caching=180")
        media.addOption(":live-caching=180")
        media.addOption(":clock-jitter=0")
        media.addOption(":clock-synchro=0")
        media.addOption(":drop-late-frames")
        media.addOption(":skip-frames")
        player.media = media

        DispatchQueue.main.async { [weak self] in
            guard let self, !self.stoppedByOwner else { return }
            if self.vlcDrawable == nil {
                let view = UIView(frame: CGRect(x: 0, y: 0, width: 960, height: 540))
                view.backgroundColor = .black
                self.vlcDrawable = view
            }
            self.player.drawable = self.vlcDrawable
        }

        // xADAS deliberately delays play briefly after media/drawable setup.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
            guard let self, !self.stoppedByOwner else { return }
            if self.player.drawable == nil {
                self.player.drawable = self.vlcDrawable
            }
            self.player.play()
        }
    }

    func stop() {
        stoppedByOwner = true
        reconnectWorkItem?.cancel()
        reconnectWorkItem = nil
        stopSnapshotLoop()
        player.stop()
        player.drawable = nil
        onStateChanged?(.idle)
    }

    func mediaPlayerStateChanged(_ newState: VLCMediaPlayerState) {
        switch newState {
        case .opening:
            onStateChanged?(.connecting)
        case .playing:
            consecutiveFailures = 0
            lastFrameAt = ProcessInfo.processInfo.systemUptime
            // .playing means RTSP/VLC state only. Actual frame delivery is
            // established by snapshotTaken and the CVPixelBuffer callback.
            startSnapshotLoop()
        case .error:
            stopSnapshotLoop()
            scheduleReconnect(reason: "VLC RTSP error")
        case .stopped:
            stopSnapshotLoop()
            if !stoppedByOwner { scheduleReconnect(reason: "VLC RTSP stopped") }
        default:
            break
        }
    }

    private func scheduleReconnect(reason: String) {
        guard reconnectWorkItem == nil, !stoppedByOwner else { return }
        consecutiveFailures += 1
        let delay = min(5.0, 0.8 + Double(consecutiveFailures - 1) * 0.8)
        onStateChanged?(.failed("\(reason); retry \(String(format: "%.1f", delay))s"))
        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.stoppedByOwner else { return }
            self.reconnectWorkItem = nil
            self.startPlayer()
        }
        reconnectWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    private func startSnapshotLoop() {
        guard snapshotTimer == nil else { return }
        lastFrameAt = ProcessInfo.processInfo.systemUptime
        snapshotTimer = Timer.scheduledTimer(withTimeInterval: 0.18, repeats: true) { [weak self] _ in self?.requestSnapshot() }
        watchdogTimer = Timer.scheduledTimer(withTimeInterval: 0.8, repeats: true) { [weak self] _ in
            guard let self, self.player.state == .playing, !self.frameProcessing,
                  ProcessInfo.processInfo.systemUptime - self.lastFrameAt > 2.4 else { return }
            self.scheduleReconnect(reason: "A500S video stalled")
        }
        requestSnapshot()
    }

    private func stopSnapshotLoop() {
        snapshotTimer?.invalidate(); snapshotTimer = nil
        watchdogTimer?.invalidate(); watchdogTimer = nil
        snapshotInFlight = false
        frameProcessing = false
        if let snapshotPath { try? FileManager.default.removeItem(atPath: snapshotPath) }
        snapshotPath = nil
    }

    private func requestSnapshot() {
        guard player.state == .playing, !snapshotInFlight, !frameProcessing else { return }
        snapshotCounter &+= 1
        let path = FileManager.default.temporaryDirectory.appendingPathComponent("das70mai-a500s-\(snapshotCounter % 2).png").path
        try? FileManager.default.removeItem(atPath: path)
        snapshotPath = path
        snapshotInFlight = true
        player.saveVideoSnapshot(at: path, withWidth: 960, andHeight: 540)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { [weak self] in
            guard let self, self.snapshotInFlight else { return }
            self.snapshotInFlight = false
        }
    }

    @objc private func snapshotTaken(_ notification: Notification) {
        guard let path = snapshotPath else { snapshotInFlight = false; return }
        snapshotInFlight = false
        snapshotPath = nil
        frameProcessing = true
        lastFrameAt = ProcessInfo.processInfo.systemUptime
        // Only a real decoded snapshot is allowed to promote A500S to streaming.
        onStateChanged?(.streaming)
        frameQueue.async { [weak self] in
            guard let self, let image = UIImage(contentsOfFile: path), let cgImage = image.cgImage,
                  let pixelBuffer = Self.makePixelBuffer(from: cgImage) else {
                try? FileManager.default.removeItem(atPath: path)
                DispatchQueue.main.async { [weak self] in self?.frameProcessing = false }
                return
            }
            try? FileManager.default.removeItem(atPath: path)
            self.onPixelBuffer?(pixelBuffer)
            DispatchQueue.main.async { [weak self] in self?.frameProcessing = false }
        }
    }

    private static func makePixelBuffer(from image: CGImage) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [kCVPixelBufferCGImageCompatibilityKey: true, kCVPixelBufferCGBitmapContextCompatibilityKey: true, kCVPixelBufferIOSurfacePropertiesKey: [:]]
        var buffer: CVPixelBuffer?
        guard CVPixelBufferCreate(kCFAllocatorDefault, image.width, image.height, kCVPixelFormatType_32BGRA, attrs as CFDictionary, &buffer) == kCVReturnSuccess,
              let buffer else { return nil }
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer), let colorSpace = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: base, width: image.width, height: image.height, bitsPerComponent: 8,
                                      bytesPerRow: CVPixelBufferGetBytesPerRow(buffer), space: colorSpace,
                                      bitmapInfo: CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue) else { return nil }
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return buffer
    }
}
