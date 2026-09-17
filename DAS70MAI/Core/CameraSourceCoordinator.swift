import Foundation

enum CameraSelection: String, Sendable {
    case a500s
    case iPhoneRearCamera
}

/// Camera source is explicitly selected by the user.
/// iPhone rear camera exists as a test source; it is NOT an automatic fallback.
actor CameraSourceCoordinator {
    private let a500s: VideoSource
    private let rearCamera: VideoSource
    private var selection: CameraSelection
    var onFrame: (@Sendable (VideoFrame) -> Void)?
    var onSourceChanged: (@Sendable (VideoSourceKind) -> Void)?

    init(a500s: VideoSource, rearCamera: VideoSource, initialSelection: CameraSelection = .iPhoneRearCamera) {
        precondition(a500s.kind == .a500s)
        precondition(rearCamera.kind == .iPhoneRearCamera)
        self.a500s = a500s
        self.rearCamera = rearCamera
        self.selection = initialSelection
    }

    func start() {
        a500s.onFrame = { [weak self] frame in Task { await self?.accept(frame) } }
        rearCamera.onFrame = { [weak self] frame in Task { await self?.accept(frame) } }
        startSelectedSource()
    }

    func select(_ newSelection: CameraSelection) {
        guard selection != newSelection else { return }
        stopSelectedSource()
        selection = newSelection
        startSelectedSource()
    }

    func stop() {
        a500s.stop()
        rearCamera.stop()
    }

    private func startSelectedSource() {
        switch selection {
        case .a500s:
            rearCamera.stop()
            a500s.start()
            onSourceChanged?(.a500s)
        case .iPhoneRearCamera:
            a500s.stop()
            rearCamera.start()
            onSourceChanged?(.iPhoneRearCamera)
        }
    }

    private func stopSelectedSource() {
        switch selection {
        case .a500s: a500s.stop()
        case .iPhoneRearCamera: rearCamera.stop()
        }
    }

    private func accept(_ frame: VideoFrame) {
        let expected: VideoSourceKind = selection == .a500s ? .a500s : .iPhoneRearCamera
        guard frame.source == expected else { return }
        onFrame?(frame)
    }
}
