import Foundation
import IPCamKit

/// Owns the A500S RTSP session. H.264 access units are emitted immediately so the
/// decoder/ADAS stage can discard stale frames instead of building a playback queue.
final class A500SRTSPSource: @unchecked Sendable {
    enum State: Sendable, Equatable {
        case idle
        case connecting
        case streaming
        case failed(String)
    }

    var onStateChanged: (@Sendable (State) -> Void)?
    var onH264AccessUnit: (@Sendable ([Data], Double, Bool) -> Void)?

    private let profile = A500SStreamProfile()
    private var session: RTSPClientSession?
    private var task: Task<Void, Never>?

    func start() {
        stop()
        onStateChanged?(.connecting)
        A500SPreviewSession.shared.prepare(host: profile.host) { [weak self] in
            guard let self else { return }
            self.startRTSP()
        }
    }

    private func startRTSP() {
        task = Task { [weak self] in
            guard let self else { return }
            let session = RTSPClientSession(
                url: self.profile.discoveryURL.absoluteString,
                transport: .udp,
                userAgent: "DAS70MAI"
            )
            self.session = session
            do {
                let description = try await session.start()
                guard description.video?.codec == .h264 else {
                    throw StreamError.unsupportedVideoCodec
                }
                self.onStateChanged?(.streaming)
                for try await item in session.frames() {
                    guard !Task.isCancelled else { break }
                    if case .video(let frame) = item {
                        self.onH264AccessUnit?(frame.nalus, frame.timestamp, frame.isKeyframe)
                    }
                }
            } catch is CancellationError {
                // Expected when the user switches camera source.
            } catch {
                self.onStateChanged?(.failed(String(describing: error)))
            }
            await session.stop()
        }
    }

    func stop() {
        task?.cancel()
        task = nil
        let oldSession = session
        session = nil
        if let oldSession {
            Task { await oldSession.stop() }
        }
        A500SPreviewSession.shared.reset()
        onStateChanged?(.idle)
    }

    enum StreamError: Error {
        case unsupportedVideoCodec
    }
}
