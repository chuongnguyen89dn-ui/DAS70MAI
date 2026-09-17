import Foundation

/// A500S is preferred. Rear iPhone camera is fallback only.
actor CameraSourceCoordinator {
    private let a500s: VideoSource
    private let rearCamera: VideoSource
    private var active: VideoSourceKind?
    var onFrame: (@Sendable (VideoFrame) -> Void)?
    var onSourceChanged: (@Sendable (VideoSourceKind) -> Void)?

    init(a500s: VideoSource, rearCamera: VideoSource) {
        precondition(a500s.kind == .a500s)
        precondition(rearCamera.kind == .iPhoneRearCamera)
        self.a500s = a500s
        self.rearCamera = rearCamera
    }

    func start() {
        a500s.onFrame = { [weak self] frame in Task { await self?.accept(frame) } }
        rearCamera.onFrame = { [weak self] frame in Task { await self?.accept(frame) } }
        a500s.onAvailabilityChanged = { [weak self] available in
            Task { await self?.setA500SAvailable(available) }
        }
        a500s.start()
        rearCamera.start()
        switchTo(.iPhoneRearCamera)
    }

    func stop() {
        a500s.stop(); rearCamera.stop(); active = nil
    }

    private func setA500SAvailable(_ available: Bool) {
        switchTo(available ? .a500s : .iPhoneRearCamera)
    }

    private func switchTo(_ source: VideoSourceKind) {
        guard active != source else { return }
        active = source
        onSourceChanged?(source)
    }

    private func accept(_ frame: VideoFrame) {
        guard frame.source == active else { return }
        onFrame?(frame)
    }
}
