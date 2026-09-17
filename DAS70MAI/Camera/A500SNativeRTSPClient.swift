import Foundation
import Network

private enum A500STransportMode: Equatable { case udp, tcp }

/// Full xADAS-style 70mai RTSP/RTP transport adapted to DAS callbacks.
final class A500SNativeRTSPClient: @unchecked Sendable {
    private let urls = [URL(string: "rtsp://192.168.0.1")!, URL(string: "rtsp://192.168.0.1/00000000")!]
    private let queue = DispatchQueue(label: "das70mai.rtsp.native")
    private var urlIndex = 0
    private var url: URL { urls[urlIndex] }
    private var connection: NWConnection?
    private var udpRTPConnection: NWConnection?
    private var receiveBuffer = Data()
    private var cseq = 1
    private var pendingResponse: ((Int, [String:String], Data) -> Void)?
    private var sessionID: String?
    private var playTarget: String?
    private var setupTarget: String?
    private var stopped = true
    private var receivedFirstRTP = false
    private var transportMode: A500STransportMode = .udp
    private var rtpWatchdog: DispatchWorkItem?
    private var streamWatchdog: DispatchWorkItem?
    private var keepAliveWorkItem: DispatchWorkItem?
    private var reconnectWorkItem: DispatchWorkItem?
    private var lastRTPAt: TimeInterval = 0
    private var lastDecodedFrameAt: TimeInterval = 0
    private var playStartedAt: TimeInterval = 0
    private var hasDecodedFrame = false
    private let rtpPort = NWEndpoint.Port(rawValue: 50_000)!
    private let rtcpPort = NWEndpoint.Port(rawValue: 50_001)!
    private var currentTimestamp: UInt32?
    private var accessUnit: [Data] = []
    private var fragmentedNAL: Data?
    private var latestSPS: Data?
    private var latestPPS: Data?

    var onStatus: (@Sendable (String) -> Void)?
    var onAccessUnit: (@Sendable ([Data]) -> Void)?

    func start() {
        stopped = false; urlIndex = 0; transportMode = .udp
        SeventyMaiPreviewSession.shared.prepare(host: "192.168.0.1") { [weak self] in self?.queue.async { self?.connectRTSP() } }
    }

    func stop() {
        stopped = true; rtpWatchdog?.cancel(); streamWatchdog?.cancel(); keepAliveWorkItem?.cancel(); reconnectWorkItem?.cancel()
        connection?.cancel(); udpRTPConnection?.cancel(); connection = nil; udpRTPConnection = nil
        receiveBuffer.removeAll(); pendingResponse = nil; sessionID = nil; playTarget = nil; setupTarget = nil
        receivedFirstRTP = false; currentTimestamp = nil; accessUnit.removeAll(); fragmentedNAL = nil; latestSPS = nil; latestPPS = nil
    }

    func noteDecodedFrame() { queue.async { [weak self] in guard let self, !self.stopped else { return }; self.hasDecodedFrame = true; self.lastDecodedFrameAt = ProcessInfo.processInfo.systemUptime } }

    private func connectRTSP() {
        guard !stopped, let hostName = url.host, let port = NWEndpoint.Port(rawValue: UInt16(url.port ?? 554)) else { report("70MAI URL INVALID"); return }
        resetNetworkState()
        let c = NWConnection(host: .init(hostName), port: port, using: .tcp); connection = c
        c.stateUpdateHandler = { [weak self, weak c] state in
            guard let self, let c, !self.stopped, self.connection === c else { return }
            switch state {
            case .ready: self.report("70MAI RTSP CONNECTED • \(self.transportMode == .udp ? "UDP" : "TCP")"); self.receiveLoop(); self.describe()
            case .failed(let e): self.report("70MAI RTSP ERROR • \(e.localizedDescription)"); self.scheduleReconnect(alternateTransport: true)
            case .waiting(let e): self.report("70MAI WAITING • \(e.localizedDescription)")
            default: break
            }
        }; c.start(queue: queue)
    }

    private func resetNetworkState() {
        rtpWatchdog?.cancel(); streamWatchdog?.cancel(); keepAliveWorkItem?.cancel(); connection?.cancel(); udpRTPConnection?.cancel()
        rtpWatchdog=nil; streamWatchdog=nil; keepAliveWorkItem=nil; connection=nil; udpRTPConnection=nil; receiveBuffer.removeAll(); pendingResponse=nil; sessionID=nil; playTarget=nil; setupTarget=nil; cseq=1; receivedFirstRTP=false; lastRTPAt=0; lastDecodedFrameAt=0; playStartedAt=0; hasDecodedFrame=false; currentTimestamp=nil; accessUnit.removeAll(); fragmentedNAL=nil
    }

    private func retryUsingTCP() { guard !stopped, transportMode == .udp else { return }; report("70MAI UDP NO RTP • TRYING TCP"); transportMode = .tcp; connectRTSP() }

    private func startUDPReceiver(serverPort: NWEndpoint.Port, completion: @escaping () -> Void) {
        guard let hostName=url.host else { report("70MAI UDP HOST INVALID"); return }
        let p=NWParameters.udp; p.requiredLocalEndpoint = .hostPort(host:.ipv4(IPv4Address("0.0.0.0")!),port:rtpPort)
        let udp=NWConnection(host:.init(hostName),port:serverPort,using:p); udpRTPConnection=udp
        udp.stateUpdateHandler={ [weak self,weak udp] state in guard let self,let udp,!self.stopped,self.udpRTPConnection === udp else{return}; switch state{case .ready:self.report("70MAI RTP/UDP READY");self.receiveUDP(on:udp);completion();case .failed(let e):self.report("70MAI UDP ERROR • \(e.localizedDescription)");self.scheduleReconnect(alternateTransport:true);case .waiting(let e):self.report("70MAI UDP WAITING • \(e.localizedDescription)");default:break} }; udp.start(queue:queue)
    }
    private func receiveUDP(on c:NWConnection){c.receiveMessage{[weak self,weak c] d,_,_,e in guard let self,let c,!self.stopped,self.udpRTPConnection === c else{return};if let d,!d.isEmpty{self.consumeRTP(d)};if let e{self.report("70MAI UDP RECEIVE ERROR • \(e.localizedDescription)");self.scheduleReconnect(alternateTransport:true)}else{self.receiveUDP(on:c)}}}

    private func describe(){sendRequest(method:"DESCRIBE",target:url.absoluteString,headers:["Accept":"application/sdp"]){[weak self] code,h,b in guard let self else{return};guard code==200 else{self.report("70MAI DESCRIBE FAILED • \(code)");self.scheduleReconnect(alternateTransport:true);return};guard let sdp=String(data:b,encoding:.utf8) else{self.report("70MAI SDP INVALID");self.scheduleReconnect(alternateTransport:true);return};let base=h["content-base"] ?? h["content-location"] ?? self.directoryURL(self.url.absoluteString);guard let track=self.videoTrackURL(from:sdp,baseURL:base) else{self.report("70MAI SDP VIDEO NOT FOUND");self.scheduleReconnect(alternateTransport:true);return};self.playTarget=self.presentationURL(from:sdp,baseURL:base);self.setupTarget=track;self.readSDPParameterSets(sdp);self.setup(trackURL:track)}}

    private func setup(trackURL:String){let t=transportMode == .udp ? "RTP/AVP;unicast;client_port=\(rtpPort.rawValue)-\(rtcpPort.rawValue)" : "RTP/AVP/TCP;unicast;interleaved=0-1";sendRequest(method:"SETUP",target:trackURL,headers:["Transport":t]){[weak self] code,h,_ in guard let self else{return};guard code==200 else{self.report("70MAI SETUP FAILED • \(code)");self.scheduleReconnect(alternateTransport:true);return};if let raw=h["session"]{self.sessionID=raw.split(separator:";",maxSplits:1).first.map(String.init)};if self.transportMode == .tcp{self.report("70MAI SETUP OK • TCP");self.play();return};guard let port=self.serverRTPPort(from:h["transport"] ?? "") else{self.report("70MAI UDP PORT MISSING • TRYING TCP");self.retryUsingTCP();return};self.report("70MAI SETUP OK • UDP");self.startUDPReceiver(serverPort:port){[weak self] in self?.play()}}}
    private func serverRTPPort(from s:String)->NWEndpoint.Port?{guard let r=s.range(of:"server_port=",options:.caseInsensitive) else{return nil};let d=s[r.upperBound...].prefix{$0.isNumber};guard let v=UInt16(d) else{return nil};return NWEndpoint.Port(rawValue:v)}
    private func play(){sendPlay(target:playTarget ?? directoryURL(url.absoluteString),allowTrackFallback:true)}
    private func sendPlay(target:String,allowTrackFallback:Bool){var h=["Range":"npt=0.000-"];if let sessionID{h["Session"]=sessionID};sendRequest(method:"PLAY",target:target,headers:h){[weak self] code,_,_ in guard let self else{return};if code==200{self.report("70MAI PLAYING • WAITING RTP • \(self.transportMode == .udp ? "UDP" : "TCP")");self.playStartedAt=ProcessInfo.processInfo.systemUptime;self.startRTPWatchdog();self.scheduleStreamWatchdog();self.scheduleKeepAlive();return};if code==404,allowTrackFallback,let setup=self.setupTarget,setup != target{self.report("70MAI PLAY RETRY • TRACK URI");self.sendPlay(target:setup,allowTrackFallback:false);return};self.report("70MAI PLAY FAILED • \(code)");self.scheduleReconnect(alternateTransport:true)}}

    private func startRTPWatchdog(){rtpWatchdog?.cancel();let i=DispatchWorkItem{[weak self] in guard let self,!self.stopped,!self.receivedFirstRTP else{return};if self.transportMode == .udp{self.retryUsingTCP()}else{self.report("70MAI NO RTP • TCP")}};rtpWatchdog=i;queue.asyncAfter(deadline:.now()+2.5,execute:i)}
    private func scheduleStreamWatchdog(){streamWatchdog?.cancel();let i=DispatchWorkItem{[weak self] in guard let self,!self.stopped else{return};let n=ProcessInfo.processInfo.systemUptime;let stalled=(self.receivedFirstRTP && n-self.lastRTPAt>2)||(self.hasDecodedFrame && n-self.lastDecodedFrameAt>2)||(!self.hasDecodedFrame && self.playStartedAt>0 && n-self.playStartedAt>4);if stalled{self.report("70MAI STREAM STALLED • RECOVERING");self.scheduleReconnect(alternateTransport:true)}else{self.scheduleStreamWatchdog()}};streamWatchdog=i;queue.asyncAfter(deadline:.now()+1,execute:i)}
    private func scheduleKeepAlive(){keepAliveWorkItem?.cancel();let i=DispatchWorkItem{[weak self] in guard let self,!self.stopped else{return};var h:[String:String]=[:];if let s=self.sessionID{h["Session"]=s};self.sendRequest(method:"OPTIONS",target:self.playTarget ?? self.directoryURL(self.url.absoluteString),headers:h){[weak self] code,_,_ in guard let self,!self.stopped else{return};if code==0 || code>=500{self.report("70MAI KEEPALIVE FAILED • RECOVERING");self.scheduleReconnect(alternateTransport:true)}else{self.scheduleKeepAlive()}}};keepAliveWorkItem=i;queue.asyncAfter(deadline:.now()+12,execute:i)}
    private func scheduleReconnect(alternateTransport:Bool){guard !stopped,reconnectWorkItem==nil else{return};streamWatchdog?.cancel();keepAliveWorkItem?.cancel();rtpWatchdog?.cancel();let i=DispatchWorkItem{[weak self] in guard let self,!self.stopped else{return};self.reconnectWorkItem=nil;if alternateTransport{self.transportMode=self.transportMode == .udp ? .tcp:.udp};self.connectRTSP()};reconnectWorkItem=i;queue.asyncAfter(deadline:.now()+0.6,execute:i)}

    private func sendRequest(method:String,target:String,headers:[String:String],completion:@escaping(Int,[String:String],Data)->Void){guard let connection,!stopped else{return};var lines=["\(method) \(target) RTSP/1.0","CSeq: \(cseq)","User-Agent: xADAS-iOS/native-rtsp"];cseq+=1;for(k,v) in headers{lines.append("\(k): \(v)")};lines.append("");lines.append("");pendingResponse=completion;connection.send(content:lines.joined(separator:"\r\n").data(using:.utf8),completion:.contentProcessed{[weak self] e in if let e{self?.report("70MAI SEND ERROR • \(e.localizedDescription)");self?.scheduleReconnect(alternateTransport:true)}})}
    private func receiveLoop(){guard let connection,!stopped else{return};connection.receive(minimumIncompleteLength:1,maximumLength:64*1024){[weak self] d,_,complete,e in guard let self,!self.stopped,self.connection === connection else{return};if let d,!d.isEmpty{self.receiveBuffer.append(d);self.consumeBuffer()};if let e{self.report("70MAI RECEIVE ERROR • \(e.localizedDescription)");self.scheduleReconnect(alternateTransport:true)}else if complete{self.scheduleReconnect(alternateTransport:true)}else{self.receiveLoop()}}}
    private func consumeBuffer(){while !receiveBuffer.isEmpty{if receiveBuffer.first==0x24{guard receiveBuffer.count>=4 else{return};let ch=receiveBuffer[1];let len=(Int(receiveBuffer[2])<<8)|Int(receiveBuffer[3]);guard receiveBuffer.count>=4+len else{return};let p=Data(receiveBuffer[4..<(4+len)]);receiveBuffer.removeSubrange(0..<(4+len));if ch==0{consumeRTP(p)};continue};guard let r=receiveBuffer.range(of:Data("\r\n\r\n".utf8)) else{return};let end=r.upperBound;guard let text=String(data:receiveBuffer[..<end],encoding:.utf8) else{receiveBuffer.removeAll();return};let h=parseHeaders(text);let len=h["content-length"].flatMap(Int.init) ?? 0;guard receiveBuffer.count>=end+len else{return};let b=Data(receiveBuffer[end..<(end+len)]);receiveBuffer.removeSubrange(0..<(end+len));let code=text.components(separatedBy:"\r\n").first?.split(separator:" ").dropFirst().first.flatMap{Int($0)} ?? 0;let cb=pendingResponse;pendingResponse=nil;cb?(code,h,b)}}
    private func parseHeaders(_ text:String)->[String:String]{var r:[String:String]=[:];for l in text.components(separatedBy:"\r\n").dropFirst(){guard let c=l.firstIndex(of:":") else{continue};r[l[..<c].trimmingCharacters(in:.whitespacesAndNewlines).lowercased()]=l[l.index(after:c)...].trimmingCharacters(in:.whitespacesAndNewlines)};return r}
    private func videoTrackURL(from sdp:String,baseURL:String)->String?{var video=false;for raw in sdp.components(separatedBy:.newlines){let l=raw.trimmingCharacters(in:.whitespacesAndNewlines);if l.hasPrefix("m="){video=l.hasPrefix("m=video")};guard video,l.hasPrefix("a=control:") else{continue};return resolveControlURL(String(l.dropFirst("a=control:".count)),baseURL:baseURL)};return nil}
    private func presentationURL(from sdp:String,baseURL:String)->String{for raw in sdp.components(separatedBy:.newlines){let l=raw.trimmingCharacters(in:.whitespacesAndNewlines);if l.hasPrefix("m="){break};guard l.hasPrefix("a=control:") else{continue};let c=String(l.dropFirst("a=control:".count));if c=="*"{return directoryURL(baseURL)};return resolveControlURL(c,baseURL:baseURL)};return directoryURL(baseURL)}
    private func resolveControlURL(_ c:String,baseURL:String)->String{if c.lowercased().hasPrefix("rtsp://"){return c};let b=directoryURL(baseURL);return URL(string:c,relativeTo:URL(string:b))?.absoluteString ?? b+c}
    private func directoryURL(_ v:String)->String{v.hasSuffix("/") ? v:v+"/"}
    private func readSDPParameterSets(_ sdp:String){guard let r=sdp.range(of:"sprop-parameter-sets=") else{return};let v=sdp[r.upperBound...].prefix{$0 != ";" && $0 != "\r" && $0 != "\n"};let p=v.split(separator:",",maxSplits:1);guard p.count==2,let s=Data(base64Encoded:String(p[0])),let q=Data(base64Encoded:String(p[1])) else{return};latestSPS=s;latestPPS=q;emitParameterSets(s,q)}
    private func emitParameterSets(_ s:Data,_ p:Data){onAccessUnit?([avcc(s),avcc(p)])}
    private func consumeRTP(_ packet:Data){guard packet.count>=12 else{return};lastRTPAt=ProcessInfo.processInfo.systemUptime;if !receivedFirstRTP{receivedFirstRTP=true;rtpWatchdog?.cancel();rtpWatchdog=nil;report("70MAI RTP RECEIVING • \(transportMode == .udp ? "UDP":"TCP")")};let first=packet[0],second=packet[1],cc=Int(first&0x0F),ext=(first&0x10) != 0,marker=(second&0x80) != 0,t=UInt32(packet[4])<<24|UInt32(packet[5])<<16|UInt32(packet[6])<<8|UInt32(packet[7]);var o=12+cc*4;guard packet.count>=o else{return};if ext{guard packet.count>=o+4 else{return};let w=(Int(packet[o+2])<<8)|Int(packet[o+3]);o += 4+w*4;guard packet.count>=o else{return}};guard o<packet.count else{return};if currentTimestamp != nil,currentTimestamp != t,!accessUnit.isEmpty{flushAccessUnit()};currentTimestamp=t;let payload=Data(packet[o...]);guard let f=payload.first else{return};switch f&0x1F{case 1...23:appendNAL(payload);case 24:consumeSTAPA(payload);case 28:consumeFUA(payload);default:break};if marker{flushAccessUnit()}}
    private func appendNAL(_ n:Data){guard let f=n.first else{return};switch f&0x1F{case 7:latestSPS=n;if let p=latestPPS{emitParameterSets(n,p)};case 8:latestPPS=n;if let s=latestSPS{emitParameterSets(s,n)};default:break};accessUnit.append(n)}
    private func consumeSTAPA(_ p:Data){var o=1;while o+2<=p.count{let l=(Int(p[o])<<8)|Int(p[o+1]);o+=2;guard l>0,o+l<=p.count else{return};appendNAL(Data(p[o..<(o+l)]));o+=l}}
    private func consumeFUA(_ p:Data){guard p.count>=2 else{return};let i=p[0],h=p[1],start=(h&0x80) != 0,end=(h&0x40) != 0,r=(i&0xE0)|(h&0x1F);if start{fragmentedNAL=Data([r]);fragmentedNAL?.append(p.dropFirst(2))}else{fragmentedNAL?.append(p.dropFirst(2))};if end,let n=fragmentedNAL{fragmentedNAL=nil;appendNAL(n)}}
    private func flushAccessUnit(){guard !accessUnit.isEmpty else{currentTimestamp=nil;return};let n=accessUnit;accessUnit.removeAll(keepingCapacity:true);currentTimestamp=nil;onAccessUnit?(n.map(avcc))}
    private func avcc(_ n:Data)->Data{var len=UInt32(n.count).bigEndian;var d=Data(bytes:&len,count:4);d.append(n);return d}
    private func report(_ s:String){DispatchQueue.main.async{[weak self] in self?.onStatus?(s)}}
}
