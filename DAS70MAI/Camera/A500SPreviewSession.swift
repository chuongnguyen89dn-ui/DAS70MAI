import CryptoKit
import Darwin
import Foundation

/// Initializes the A500S live-preview session before RTSP is opened.
/// The token is read at runtime from Info.plist key `SeventyMaiToken`.
/// No token is committed to source control.
final class A500SPreviewSession: @unchecked Sendable {
    static let shared = A500SPreviewSession()

    private let queue = DispatchQueue(label: "das70mai.a500s.preview-session")
    private var keepAlive: DispatchSourceTimer?
    private var host = "192.168.0.1"
    private var token = ""
    private var preparing = false
    private var prepared = false
    private var completions: [@Sendable () -> Void] = []

    private init() {}

    func prepare(host: String, completion: @escaping @Sendable () -> Void) {
        queue.async {
            self.completions.append(completion)
            if self.prepared {
                self.finishCompletions()
                return
            }
            guard !self.preparing else { return }
            self.preparing = true
            self.host = host
            self.token = (Bundle.main.object(forInfoDictionaryKey: "SeventyMaiToken") as? String)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

            guard !self.token.isEmpty, self.token != "__SEVENTYMAI_TOKEN__" else {
                self.preparing = false
                self.finishCompletions()
                return
            }

            self.request(command: "getstreamlicensed.cgi") {
                self.request(command: "setwifistream.cgi", parameters: [("sensor", "Front")]) {
                    self.register {
                        self.preparing = false
                        self.prepared = true
                        self.startKeepAlive()
                        self.finishCompletions()
                    }
                }
            }
        }
    }

    func reset() {
        queue.async {
            self.keepAlive?.cancel()
            self.keepAlive = nil
            self.prepared = false
            self.preparing = false
            self.completions.removeAll()
        }
    }

    private func register(completion: (@Sendable () -> Void)? = nil) {
        request(command: "client.cgi", parameters: [
            ("operation", "register"),
            ("ip", Self.wifiIPv4Address() ?? "192.168.0.2")
        ], completion: completion)
    }

    private func startKeepAlive() {
        keepAlive?.cancel()
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 2, repeating: 2)
        timer.setEventHandler { [weak self] in self?.register() }
        keepAlive = timer
        timer.resume()
    }

    private func request(command: String, parameters: [(String, String)] = [], completion: (@Sendable () -> Void)? = nil) {
        let timestamp = String(Int(Date().timeIntervalSince1970))
        let params = parameters.map { "&-\($0.0)=\($0.1)" }.joined()
        let unsigned = "\(command)?\(params)&-timestamp=\(timestamp)"
        let signature = Self.md5(unsigned + token)
        guard let url = URL(string: "http://\(host)/cgi-bin/\(unsigned)&-signkey=\(signature)") else {
            completion?()
            return
        }
        var request = URLRequest(url: url)
        request.timeoutInterval = 1.5
        URLSession.shared.dataTask(with: request) { _, _, _ in
            self.queue.async { completion?() }
        }.resume()
    }

    private func finishCompletions() {
        let pending = completions
        completions.removeAll()
        pending.forEach { $0() }
    }

    private static func md5(_ value: String) -> String {
        Insecure.MD5.hash(data: Data(value.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    private static func wifiIPv4Address() -> String? {
        var pointer: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&pointer) == 0, let first = pointer else { return nil }
        defer { freeifaddrs(pointer) }
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            let item = interface.pointee
            if let socketAddress = item.ifa_addr,
               socketAddress.pointee.sa_family == UInt8(AF_INET),
               String(cString: item.ifa_name) == "en0" {
                var address = socketAddress.pointee
                var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(&address, socklen_t(socketAddress.pointee.sa_len), &buffer,
                               socklen_t(buffer.count), nil, 0, NI_NUMERICHOST) == 0 {
                    return String(cString: buffer)
                }
            }
            current = item.ifa_next
        }
        return nil
    }
}
