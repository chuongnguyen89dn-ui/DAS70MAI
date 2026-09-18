import AVFoundation
import SwiftUI

struct CameraPreview: UIViewRepresentable {
    let session: AVCaptureSession

    func makeUIView(context: Context) -> PreviewView {
        let view = PreviewView()
        view.attach(session: session)
        return view
    }

    func updateUIView(_ uiView: PreviewView, context: Context) {
        uiView.attach(session: session)
    }
}

final class PreviewView: UIView {
    private var rotationCoordinator: AnyObject?
    private var rotationObservation: NSKeyValueObservation?
    private weak var attachedSession: AVCaptureSession?

    override class var layerClass: AnyClass { AVCaptureVideoPreviewLayer.self }
    var videoPreviewLayer: AVCaptureVideoPreviewLayer { layer as! AVCaptureVideoPreviewLayer }

    func attach(session: AVCaptureSession) {
        videoPreviewLayer.videoGravity = .resizeAspect
        guard attachedSession !== session else { return }
        attachedSession = session
        videoPreviewLayer.session = session
        configureRotation()
    }

    private func configureRotation() {
        rotationObservation = nil
        rotationCoordinator = nil
        guard let device = attachedSession?.inputs
            .compactMap({ ($0 as? AVCaptureDeviceInput)?.device })
            .first(where: { $0.hasMediaType(.video) }) else {
            DispatchQueue.main.async { [weak self] in self?.configureRotation() }
            return
        }

        if #available(iOS 17.0, *) {
            let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: videoPreviewLayer)
            rotationCoordinator = coordinator
            applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
            rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.initial, .new]) { [weak self] coordinator, _ in
                DispatchQueue.main.async {
                    self?.applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
                }
            }
        } else if let connection = videoPreviewLayer.connection, connection.isVideoOrientationSupported {
            connection.videoOrientation = .portrait
        }
    }

    @available(iOS 17.0, *)
    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = videoPreviewLayer.connection,
              connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }
}
