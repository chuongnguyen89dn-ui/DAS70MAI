import SwiftUI

struct DriveView: View {
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @AppStorage(CameraSource.selectionKey) private var cameraSourceRaw = CameraSourceChoice.seventyMai.rawValue
    @State private var rtspStatus = "70MAI STARTING"
    @State private var restartToken = UUID()
    @State private var visionSuspended = false
    @State private var soundEnabled = true
    @State private var vibrationEnabled = true
    @StateObject private var a500sProcessor = FrameProcessor()
    @StateObject private var cameraManager = CameraManager()

    private var selectedSource: CameraSourceChoice { CameraSourceChoice(rawValue: cameraSourceRaw) ?? .seventyMai }
    private var activeProcessor: FrameProcessor { selectedSource == .iPhone ? cameraManager.frameProcessor : a500sProcessor }
    private var isLandscape: Bool { verticalSizeClass == .compact }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                cameraStage(cornerRadius: 18).frame(maxHeight: .infinity).clipped()
                HStack {
                    Text(yoloStatus)
                    Spacer()
                    Text(metricsText)
                }.font(.caption).foregroundStyle(activeProcessor.dasInferenceError == nil ? Color.secondary : Color.red)
                HStack(spacing: 16) {
                    Toggle(isOn: $soundEnabled) { Label("Sound", systemImage: soundEnabled ? "speaker.wave.2.fill" : "speaker.slash.fill") }.toggleStyle(.switch)
                    Toggle(isOn: $vibrationEnabled) { Label("Vibration", systemImage: "iphone.radiowaves.left.and.right") }.toggleStyle(.switch)
                }.font(.caption)
                VStack(alignment: .leading, spacing: 6) {
                    Text("Camera source").font(.caption).foregroundStyle(.secondary)
                    Picker("Camera source", selection: $cameraSourceRaw) {
                        Text("70mai A500S").tag(CameraSourceChoice.seventyMai.rawValue)
                        Text("iPhone Rear").tag(CameraSourceChoice.iPhone.rawValue)
                    }.pickerStyle(.segmented)
                }
            }.padding().foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear { a500sProcessor.dasRotate180 = true; a500sProcessor.effectiveFocalPixelsAt1920 = 890; cameraManager.frameProcessor.dasRotate180 = false; configureSource(); applyFeedback() }
        .onChange(of: cameraSourceRaw) { _ in configureSource() }
        .onChange(of: soundEnabled) { _ in applyFeedback() }
        .onChange(of: vibrationEnabled) { _ in applyFeedback() }
        .onChange(of: scenePhase) { phase in
            if phase == .active { visionSuspended = false; configureSource() }
            else if phase == .background { visionSuspended = true; cameraManager.stop() }
        }
        .persistentSystemOverlays(.hidden)
    }

    private var header: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("DAS70MAI").font(.title2.bold())
                Text(selectedSource == .seventyMai ? "70mai A500S · \(rtspStatus)" : "iPhone Rear · Test").font(.caption).foregroundStyle(.secondary)
            }
            Spacer(); riskBadge
        }
    }

    private var riskBadge: some View {
        Text(riskText).font(.caption.bold()).padding(.horizontal,10).padding(.vertical,6)
            .background(riskColor.opacity(0.85)).clipShape(Capsule())
    }

    @ViewBuilder private func cameraStage(cornerRadius: CGFloat) -> some View {
        ZStack {
            Color.black
            if !visionSuspended {
                if selectedSource == .iPhone {
                    CameraPreview(session: cameraManager.session)
                } else {
                    RootlessSeventyMaiPlayerView(urlString: CameraSource.seventyMaiURL, restartToken: restartToken, frameProcessor: a500sProcessor, statusText: $rtspStatus)
                }
            }
            LaneGuideOverlay(showLabel: true)
            if let lane = activeProcessor.dasLaneDetection { DASLaneOverlay(lane: lane) }
            DASDetectionOverlay(detections: activeProcessor.dasDetections,
                                imageSize: CGSize(width: max(activeProcessor.frameWidth,1), height: max(activeProcessor.frameHeight,1)))
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }

    private var yoloStatus: String {
        if let e = activeProcessor.dasInferenceError { return "YOLO ERROR · \(e)" }
        if activeProcessor.dasInferenceMS > 0 { return "YOLO READY · \(activeProcessor.dasDetections.count) objects · lanes \(activeProcessor.dasLaneDetection == nil ? 0 : 1)" }
        return "YOLO LOADING"
    }
    private var metricsText: String {
        activeProcessor.dasInferenceMS > 0 ? String(format:"CAM %.0f FPS · AI %.0f ms · age %.0f ms · drop %.1f%%",activeProcessor.dasFPS,activeProcessor.dasInferenceMS,activeProcessor.dasPipelineAgeMS,activeProcessor.dasDropPercent) : "-- ms"
    }
    private var riskText: String { switch activeProcessor.dasRisk.level { case .clear:"CLEAR"; case .caution:"CAUTION"; case .warning:"WARNING" } }
    private var riskColor: Color { switch activeProcessor.dasRisk.level { case .clear:.green; case .caution:.orange; case .warning:.red } }

    private func applyFeedback() {
        a500sProcessor.setDASSoundEnabled(soundEnabled); a500sProcessor.setDASVibrationEnabled(vibrationEnabled)
        cameraManager.frameProcessor.setDASSoundEnabled(soundEnabled); cameraManager.frameProcessor.setDASVibrationEnabled(vibrationEnabled)
    }
    private func configureSource() {
        visionSuspended=false
        if selectedSource == .iPhone { cameraManager.start() }
        else { cameraManager.stop(); restartA500S() }
    }
    private func restartA500S() {
        rtspStatus="70MAI STARTING"; restartToken=UUID()
    }
}

private struct DASDetectionOverlay: View {
    let detections:[ADASDetection]; let imageSize:CGSize
    var body: some View {
        GeometryReader { g in
            ForEach(detections) { d in
                let r=displayRect(d.boundingBox,image:imageSize,view:g.size)
                ZStack(alignment:.topLeading) {
                    Rectangle().stroke(.yellow,lineWidth:2)
                    Text("\(d.label) \(Int(d.confidence*100))%").font(.caption2.bold()).padding(.horizontal,4).padding(.vertical,2).background(.yellow).foregroundStyle(.black)
                }.frame(width:max(r.width,1),height:max(r.height,1)).position(x:r.midX,y:r.midY)
            }
        }.allowsHitTesting(false)
    }
    private func displayRect(_ r:CGRect,image:CGSize,view:CGSize)->CGRect {
        guard image.width>1,image.height>1 else { return CGRect(x:r.minX*view.width,y:r.minY*view.height,width:r.width*view.width,height:r.height*view.height) }
        let s=max(view.width/image.width,view.height/image.height)
        let scaled=CGSize(width:image.width*s,height:image.height*s)
        let ox=(scaled.width-view.width)/2, oy=(scaled.height-view.height)/2
        // A500S inference image is rotated 180 degrees together with the display.
        return CGRect(x:r.minX*image.width*s-ox,y:r.minY*image.height*s-oy,width:r.width*image.width*s,height:r.height*image.height*s)
    }
}

private struct LaneGuideOverlay: View {
    let showLabel:Bool
    var body: some View {
        GeometryReader { g in
            ZStack {
                Path { p in
                    p.move(to:CGPoint(x:g.size.width*0.14,y:g.size.height*0.98)); p.addLine(to:CGPoint(x:g.size.width*0.43,y:g.size.height*0.48))
                    p.move(to:CGPoint(x:g.size.width*0.86,y:g.size.height*0.98)); p.addLine(to:CGPoint(x:g.size.width*0.57,y:g.size.height*0.48))
                }.stroke(.yellow.opacity(0.9),style:StrokeStyle(lineWidth:4,lineCap:.round,dash:[12,10]))
                if showLabel {
                    Text("LANE GUIDE").font(.caption2.bold()).padding(.horizontal,7).padding(.vertical,4).background(.black.opacity(0.55)).clipShape(Capsule()).position(x:g.size.width*0.5,y:g.size.height*0.44)
                }
            }
        }.allowsHitTesting(false)
    }
}


private struct DASLaneOverlay: View {
    let lane: LaneDetection
    var body: some View {
        GeometryReader { g in
            ZStack {
                lanePath(lane.leftPoints, size: g.size).stroke(.green, lineWidth: 3)
                lanePath(lane.rightPoints, size: g.size).stroke(.green, lineWidth: 3)
            }
        }.allowsHitTesting(false)
    }
    private func lanePath(_ points: [CGPoint], size: CGSize) -> Path {
        Path { p in
            guard let first = points.first else { return }
            p.move(to: CGPoint(x: first.x * size.width, y: first.y * size.height))
            for point in points.dropFirst() {
                p.addLine(to: CGPoint(x: point.x * size.width, y: point.y * size.height))
            }
        }
    }
}
