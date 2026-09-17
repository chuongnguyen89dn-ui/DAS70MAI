import Foundation

/// Keeps at most one frame so AI never works through an old-frame backlog.
actor LatestFrameStore {
    private var latest: VideoFrame?
    private(set) var replacedFrames: UInt64 = 0

    func push(_ frame: VideoFrame) {
        if latest != nil { replacedFrames += 1 }
        latest = frame
    }

    func takeLatest() -> VideoFrame? {
        defer { latest = nil }
        return latest
    }
}
