import Foundation
import Network

/// Native RTSP control path ported from xADAS. Negotiates SDP, video track, SETUP and PLAY.
final class A500SNativeRTSPClient: @unchecked Sendable {
    private let queue = DispatchQueue(label: "das70mai.rtsp.native")
    private let urls = [URL(string: "rtsp://192.168.0.1")!, URL(string: "rtsp://192.168.0.1/00000000")!]
    private var urlIndex = 0
    private var connection: NWConnection?
    private var receiveBuffer = Data()
    private var cseq = 1
    private var sessionID: String?
    private var pending: ((Int, [String: String], Data) -> Void)?
    private var stopped = true
    var onStatus: (@Sendable (String) -> Void)?
    var onNegotiated: (@Sendable (URL) -> Void)?

    func start() {
        stopped = false
        urlIndex = 0
        SeventyMaiPreviewSession.shared.prepare(host: "192.168.0.1") { [weak self] in
            self?.queue.async { self?.connect() }
        }
    }

    func stop() {
        stopped = true
        connection?.cancel()
        connection = nil
        receiveBuffer.removeAll()
        pending = nil
    }

    private func connect() {
        guard !stopped else { return }
        connection?.cancel()
        receiveBuffer.removeAll()
        pending = nil
        sessionID = nil
        cseq = 1
        let url = urls[urlIndex]
        let host = NWEndpoint.Host(url.host!)
        let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 554))!
        let c = NWConnection(host: host, port: port, using: .tcp)
        connection = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, self.connection === c, !self.stopped else { return }
            switch state {
            case .ready:
                self.report("NATIVE RTSP CONNECTED")
                self.receive()
                self.describe(url)
            case .failed(let error):
                self.report("NATIVE RTSP ERROR: \(error.localizedDescription)")
                self.tryNext()
            default: break
            }
        }
        c.start(queue: queue)
    }

    private func tryNext() {
        guard !stopped else { return }
        urlIndex = (urlIndex + 1) % urls.count
        queue.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.connect() }
    }

    private func describe(_ url: URL) {
        send("DESCRIBE", url.absoluteString, ["Accept": "application/sdp"]) { [weak self] code, headers, body in
            guard let self else { return }
            guard code == 200, let sdp = String(data: body, encoding: .utf8) else {
                self.report("DESCRIBE FAILED \(code)")
                self.tryNext()
                return
            }
            let base = headers["content-base"] ?? headers["content-location"] ?? self.directory(url.absoluteString)
            guard let track = self.videoTrack(sdp, base) else {
                self.report("SDP VIDEO NOT FOUND")
                self.tryNext()
                return
            }
            self.setup(track: track, play: self.presentation(sdp, base), source: url)
        }
    }

    private func setup(track: String, play: String, source: URL) {
        send("SETUP", track, ["Transport": "RTP/AVP/TCP;unicast;interleaved=0-1"]) { [weak self] code, headers, _ in
            guard let self else { return }
            guard code == 200 else { self.report("SETUP FAILED \(code)"); self.tryNext(); return }
            if let raw = headers["session"] { self.sessionID = raw.split(separator: ";", maxSplits: 1).first.map(String.init) }
            self.send("PLAY", play, [:]) { [weak self] code, _, _ in
                guard let self else { return }
                if code == 200 { self.report("NATIVE RTSP PLAY OK"); self.onNegotiated?(source) }
                else { self.report("PLAY FAILED \(code)"); self.tryNext() }
            }
        }
    }

    private func send(_ method: String, _ target: String, _ headers: [String: String], completion: @escaping (Int, [String: String], Data) -> Void) {
        guard let c = connection else { return }
        var request = "\(method) \(target) RTSP/1.0\r\nCSeq: \(cseq)\r\nUser-Agent: DAS70MAI/xADAS\r\n"
        cseq += 1
        if let sessionID { request += "Session: \(sessionID)\r\n" }
        for (key, value) in headers { request += "\(key): \(value)\r\n" }
        request += "\r\n"
        pending = completion
        c.send(content: request.data(using: .utf8), completion: .contentProcessed { [weak self] error in
            if let error { self?.report("RTSP SEND ERROR: \(error.localizedDescription)"); self?.tryNext() }
        })
    }

    private func receive() {
        guard let c = connection else { return }
        c.receive(minimumIncompleteLength: 1, maximumLength: 65536) { [weak self] data, _, done, error in
            guard let self else { return }
            if let data { self.receiveBuffer.append(data); self.parse() }
            if error != nil || done { self.tryNext() } else { self.receive() }
        }
    }

    private func parse() {
        while true {
            guard let range = receiveBuffer.range(of: Data("\r\n\r\n".utf8)) else { return }
            let headerData = receiveBuffer[..<range.lowerBound]
            guard let text = String(data: headerData, encoding: .utf8) else { return }
            let lines = text.components(separatedBy: "\r\n")
            guard let first = lines.first else { return }
            let code = Int(first.split(separator: " ").dropFirst().first ?? "0") ?? 0
            var headers: [String: String] = [:]
            for line in lines.dropFirst() {
                if let i = line.firstIndex(of: ":") {
                    headers[String(line[..<i]).lowercased()] = String(line[line.index(after: i)...]).trimmingCharacters(in: .whitespaces)
                }
            }
            let length = Int(headers["content-length"] ?? "0") ?? 0
            let bodyStart = range.upperBound
            guard receiveBuffer.count >= bodyStart + length else { return }
            let body = Data(receiveBuffer[bodyStart..<(bodyStart + length)])
            receiveBuffer.removeSubrange(0..<(bodyStart + length))
            let callback = pending
            pending = nil
            callback?(code, headers, body)
        }
    }

    private func videoTrack(_ sdp: String, _ base: String) -> String? {
        var video = false
        for raw in sdp.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.hasPrefix("m=") { video = line.hasPrefix("m=video") }
            if video, line.lowercased().hasPrefix("a=control:") { return resolve(String(line.dropFirst("a=control:".count)), base) }
        }
        return nil
    }

    private func presentation(_ sdp: String, _ base: String) -> String {
        for raw in sdp.components(separatedBy: .newlines) {
            let line = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if line.lowercased().hasPrefix("a=control:") {
                let value = String(line.dropFirst("a=control:".count))
                if value != "*" { return resolve(value, base) }
            }
        }
        return base
    }

    private func resolve(_ control: String, _ base: String) -> String {
        if control.hasPrefix("rtsp://") { return control }
        if control == "*" { return base }
        return base.hasSuffix("/") ? base + control : base + "/" + control
    }

    private func directory(_ value: String) -> String { value.hasSuffix("/") ? value : value + "/" }
    private func report(_ value: String) { onStatus?(value) }
}
