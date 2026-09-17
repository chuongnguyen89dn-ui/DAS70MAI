import Foundation

/// Known A500S front-preview RTSP profile.
/// The camera is reached while the iPhone is joined to the dashcam Wi-Fi hotspot.
struct A500SStreamProfile: Sendable {
    let host = "192.168.0.1"
    let port = 554
    let discoveryPath = "/livestream/12"

    var discoveryURL: URL {
        URL(string: "rtsp://\(host):\(port)\(discoveryPath)")!
    }

    /// The A500S may return a changing Content-Base (00000000, 00000001, ...).
    /// Never assume that sequence number is a stable camera selector.
    func mediaURL(contentBase: String?) -> URL {
        if let contentBase, let url = URL(string: contentBase) { return url }
        return discoveryURL
    }
}

/// Runtime policy for ADAS: freshness is more important than showing every video frame.
struct A500SLowLatencyPolicy: Sendable {
    /// RTP/UDP is preferred because observed A500S SETUP responses expose UDP unicast.
    let preferUDP = true
    /// Never accumulate decoded frames waiting for inference.
    let keepLatestFrameOnly = true
    /// Frames older than this are unsuitable for a forward-warning UI.
    let staleFrameLimitMilliseconds: Double = 250
    /// Reconnect quickly rather than leaving a frozen preview on screen.
    let reconnectAfterNoFrameMilliseconds: Double = 1_000
}
