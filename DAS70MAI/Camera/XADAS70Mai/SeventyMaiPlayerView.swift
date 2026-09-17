import CoreGraphics
import CoreVideo
import SwiftUI
import UIKit
import VLCKit

struct SeventyMaiPlayerView: UIViewRepresentable {
    let urlString: String
    let restartToken: UUID
    let frameProcessor: FrameProcessor
    @Binding var statusText: String

    func makeCoordinator() -> Coordinator {
        Coordinator(statusText: $statusText, frameProcessor: frameProcessor)
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        view.clipsToBounds = true
        view.contentMode = .scaleAspectFill
        context.coordinator.attach(view: view, urlString: urlString, restartToken: restartToken)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.statusText = $statusText
        context.coordinator.attach(view: uiView, urlString: urlString, restartToken: restartToken)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) { coordinator.stop() }

    final class Coordinator: NSObject, VLCMediaPlayerDelegate {
        fileprivate var statusText: Binding<String>; private let frameProcessor: FrameProcessor; private let player = VLCMediaPlayer(); private let frameQueue = DispatchQueue(label: "xadas.70mai.frame", qos: .userInitiated); private var currentURL:String?; private var currentRestartToken:UUID?; private weak var currentView:UIView?; private var snapshotTimer:Timer?; private var watchdogTimer:Timer?; private var reconnectWorkItem:DispatchWorkItem?; private var snapshotInFlight=false; private var frameProcessing=false; private var snapshotPath:String?; private var snapshotCounter:UInt64=0; private var stoppedByOwner=false; private var ownerRestartInProgress=false; private var lastFrameAt=ProcessInfo.processInfo.systemUptime; private var consecutiveFailures=0
        init(statusText:Binding<String>,frameProcessor:FrameProcessor){self.statusText=statusText;self.frameProcessor=frameProcessor;super.init();player.delegate=self;NotificationCenter.default.addObserver(self,selector:#selector(snapshotTaken(_:)),name:VLCMediaPlayer.snapshotTakenNotification,object:player)}
        deinit{NotificationCenter.default.removeObserver(self)}
        func attach(view:UIView,urlString:String,restartToken:UUID){currentView=view;player.drawable=view;applyFullscreenVideoAspect();guard currentURL != urlString || currentRestartToken != restartToken else{return};currentURL=urlString;currentRestartToken=restartToken;stoppedByOwner=false;consecutiveFailures=0;start(urlString:urlString)}
        private func start(urlString:String){reconnectWorkItem?.cancel();reconnectWorkItem=nil;stopSnapshotLoop();ownerRestartInProgress=true;player.stop();setStatus("70MAI CONNECTING");guard let url=URL(string:urlString),let media=VLCMedia(url:url) else{setStatus("70MAI URL INVALID");return};media.addOption(":network-caching=180");media.addOption(":live-caching=180");media.addOption(":clock-jitter=0");media.addOption(":clock-synchro=0");media.addOption(":drop-late-frames");media.addOption(":skip-frames");player.media=media;if let currentView{player.drawable=currentView;applyFullscreenVideoAspect()};DispatchQueue.main.asyncAfter(deadline:.now()+0.25){[weak self] in guard let self,!self.stoppedByOwner else{return};self.player.play();self.applyFullscreenVideoAspect();self.ownerRestartInProgress=false}}
        private func applyFullscreenVideoAspect(){let screen=UIScreen.main.bounds.size;let w=max(screen.width,screen.height),h=min(screen.width,screen.height);guard w>0,h>0 else{return};player.scaleFactor=0;player.videoAspectRatio="\(Int(w)):\(Int(h))"}
        func mediaPlayerStateChanged(_ s:VLCMediaPlayerState){switch s{case .opening:setStatus("70MAI OPENING");case .playing:consecutiveFailures=0;ownerRestartInProgress=false;applyFullscreenVideoAspect();setStatus("70MAI PLAYING • ADAS ACTIVE");startSnapshotLoop();case .paused:setStatus("70MAI PAUSED");stopSnapshotLoop();case .stopping:setStatus("70MAI STOPPING");case .stopped:stopSnapshotLoop();if !stoppedByOwner && !ownerRestartInProgress{scheduleReconnect(reason:"70MAI RECONNECTING")};case .error:stopSnapshotLoop();if !stoppedByOwner{scheduleReconnect(reason:"70MAI ERROR • AUTO RETRY")};case .nothingSpecial:setStatus("70MAI WAITING");@unknown default:setStatus("70MAI UNKNOWN STATE")}}
        func mediaPlayerBufferingChanged(_ p:Float){if p>=1{if player.state == .playing{setStatus("70MAI PLAYING • ADAS ACTIVE")}}else{setStatus(String(format:"70MAI BUFFERING %.0f%%",p*100))}}
        private func scheduleReconnect(reason:String){guard reconnectWorkItem==nil,!stoppedByOwner else{return};consecutiveFailures+=1;let delay=min(5.0,0.8+Double(consecutiveFailures-1)*0.8);setStatus("\(reason) • \(String(format:"%.1fs",delay))");let item=DispatchWorkItem{[weak self] in guard let self,!self.stoppedByOwner,let url=self.currentURL else{return};self.reconnectWorkItem=nil;self.start(urlString:url)};reconnectWorkItem=item;DispatchQueue.main.asyncAfter(deadline:.now()+delay,execute:item)}
        private func startSnapshotLoop(){guard snapshotTimer==nil else{return};lastFrameAt=ProcessInfo.processInfo.systemUptime;snapshotTimer=Timer.scheduledTimer(withTimeInterval:0.18,repeats:true){[weak self] _ in self?.requestSnapshot()};watchdogTimer=Timer.scheduledTimer(withTimeInterval:0.8,repeats:true){[weak self] _ in guard let self,self.player.state == .playing,!self.frameProcessing,ProcessInfo.processInfo.systemUptime-self.lastFrameAt>2.4 else{return};self.setStatus("70MAI VIDEO STALLED • RECOVERING");self.scheduleReconnect(reason:"70MAI AUTO RECONNECT")};requestSnapshot()}
        private func stopSnapshotLoop(){snapshotTimer?.invalidate();snapshotTimer=nil;watchdogTimer?.invalidate();watchdogTimer=nil;snapshotInFlight=false;frameProcessing=false;if let snapshotPath{try? FileManager.default.removeItem(atPath:snapshotPath)};snapshotPath=nil}
        private func requestSnapshot(){guard player.state == .playing,!snapshotInFlight,!frameProcessing else{return};snapshotCounter &+= 1;let path=FileManager.default.temporaryDirectory.appendingPathComponent("xadas-70mai-\(snapshotCounter % 2).png").path;try? FileManager.default.removeItem(atPath:path);snapshotPath=path;snapshotInFlight=true;player.saveVideoSnapshot(at:path,withWidth:960,andHeight:540);DispatchQueue.main.asyncAfter(deadline:.now()+0.45){[weak self] in guard let self,self.snapshotInFlight else{return};self.snapshotInFlight=false}}
        @objc private func snapshotTaken(_ notification:Notification){guard let path=snapshotPath else{snapshotInFlight=false;return};snapshotInFlight=false;snapshotPath=nil;frameProcessing=true;lastFrameAt=ProcessInfo.processInfo.systemUptime;frameQueue.async{[weak self] in guard let self,let image=UIImage(contentsOfFile:path),let cg=image.cgImage,let pb=Self.makePixelBuffer(from:cg) else{try? FileManager.default.removeItem(atPath:path);DispatchQueue.main.async{[weak self] in self?.frameProcessing=false};return};try? FileManager.default.removeItem(atPath:path);self.frameProcessor.process(pixelBuffer:pb);DispatchQueue.main.async{[weak self] in self?.frameProcessing=false}}}
        func stop(){stoppedByOwner=true;ownerRestartInProgress=true;reconnectWorkItem?.cancel();reconnectWorkItem=nil;stopSnapshotLoop();player.stop();player.drawable=nil;currentURL=nil;currentRestartToken=nil}
        private func setStatus(_ text:String){DispatchQueue.main.async{[weak self] in self?.statusText.wrappedValue=text}}
        private static func makePixelBuffer(from image:CGImage)->CVPixelBuffer?{let w=image.width,h=image.height;let attrs:[CFString:Any]=[kCVPixelBufferCGImageCompatibilityKey:true,kCVPixelBufferCGBitmapContextCompatibilityKey:true,kCVPixelBufferIOSurfacePropertiesKey:[:]];var pb:CVPixelBuffer?;guard CVPixelBufferCreate(kCFAllocatorDefault,w,h,kCVPixelFormatType_32BGRA,attrs as CFDictionary,&pb)==kCVReturnSuccess,let pb else{return nil};CVPixelBufferLockBaseAddress(pb,[]);defer{CVPixelBufferUnlockBaseAddress(pb,[])};guard let base=CVPixelBufferGetBaseAddress(pb),let cs=CGColorSpace(name:CGColorSpace.sRGB),let ctx=CGContext(data:base,width:w,height:h,bitsPerComponent:8,bytesPerRow:CVPixelBufferGetBytesPerRow(pb),space:cs,bitmapInfo:CGBitmapInfo.byteOrder32Little.rawValue|CGImageAlphaInfo.premultipliedFirst.rawValue) else{return nil};ctx.draw(image,in:CGRect(x:0,y:0,width:w,height:h));return pb}
    }
}
