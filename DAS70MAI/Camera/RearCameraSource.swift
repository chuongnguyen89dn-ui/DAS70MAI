import AVFoundation
import CoreVideo
import Foundation

final class RearCameraSource: NSObject, VideoSource, AVCaptureVideoDataOutputSampleBufferDelegate {
    let kind: VideoSourceKind = .iPhoneRearCamera
    var onFrame: (@Sendable (VideoFrame) -> Void)?
    var onAvailabilityChanged: (@Sendable (Bool) -> Void)?

    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "DAS70MAI.rear-camera", qos: .userInteractive)
    private var configured = false

    func start() {
        queue.async { [weak self] in
            guard let self else { return }
            do {
                if !configured { try configure() }
                session.startRunning()
                onAvailabilityChanged?(true)
            } catch {
                onAvailabilityChanged?(false)
            }
        }
    }

    func stop() {
        queue.async { [weak self] in self?.session.stopRunning() }
    }

    private func configure() throws {
        session.beginConfiguration()
        defer { session.commitConfiguration() }
        session.sessionPreset = .hd1280x720

        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            throw CameraError.rearCameraUnavailable
        }
        let input = try AVCaptureDeviceInput(device: device)
        guard session.canAddInput(input) else { throw CameraError.cannotAddInput }
        session.addInput(input)

        let output = AVCaptureVideoDataOutput()
        output.alwaysDiscardsLateVideoFrames = true
        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        output.setSampleBufferDelegate(self, queue: queue)
        guard session.canAddOutput(output) else { throw CameraError.cannotAddOutput }
        session.addOutput(output)
        configured = true
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(VideoFrame(pixelBuffer: pixelBuffer, source: .iPhoneRearCamera, receivedAt: .now))
    }

    enum CameraError: Error { case rearCameraUnavailable, cannotAddInput, cannotAddOutput }
}
