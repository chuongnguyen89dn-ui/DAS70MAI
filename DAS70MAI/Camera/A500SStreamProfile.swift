import Foundation

/// A500S front-preview RTSP discovery profile.
/// Packet captures from A500S show DESCRIBE on /livestream/12 and a dynamic
/// Content-Base such as /00000008/, followed by SETUP of track1.
struct A500SStreamProfile: Sendable {
    let host = "192.168.0.1"
    let port = 554
    let discoveryPath = "/livestream/12"

    /// Keep the URI form used by the camera's own returned Content-Base.
    /// RTSP defaults to port 554, so omitting :554 also avoids clients carrying
    /// the discovery authority into the dynamic media control URL.
    var discoveryURL: URL {
        URL(string: "rtsp://\(host)\(discoveryPath)")!
    }

    /// A500S returns a changing Content-Base (00000000, 00000001, ...).
    /// The sequence is session/dynamic state, not a stable front/rear selector.
    func mediaURL(contentBase: String?) -> URL {
        guard let contentBase else { return discoveryURL }
        let trimmed = contentBase.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return discoveryURL }
        if let absolute = URL(string: trimmed), absolute.scheme != nil { return absolute }
        return URL(string: trimmed, relativeTo: discoveryURL)?.absoluteURL ?? discoveryURL
    }

    func videoControlURL(contentBase: String?, control: String = "track1") -> URL {
        let base = mediaURL(contentBase: contentBase)
        guard !control.lowercased().hasPrefix("rtsp://") else {
            return URL(string: control) ?? base
        }
        let baseString = base.absoluteString.hasSuffix("/") ? base.absoluteString : base.absoluteString + "/"
        return URL(string: control, relativeTo: URL(string: baseString)!)?.absoluteURL ?? base
    }
}

/// Runtime policy for ADAS: freshness is more important than showing every video frame.
struct A500SLowLatencyPolicy: Sendable {
    let preferUDP = true
    let keepLatestFrameOnly = true
    let staleFrameLimitMilliseconds: Double = 250
    let reconnectAfterNoFrameMilliseconds: Double = 1_000
}
