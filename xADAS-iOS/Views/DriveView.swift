import SwiftUI

struct DriveView: View {
    @Environment(\.scenePhase) private var scenePhase
    @AppStorage(CameraSource.selectionKey) private var cameraSourceRaw = CameraSourceChoice.seventyMai.rawValue
    @State private var rtspStatus = "70MAI STARTING"
    @State private var restartToken = UUID()
    @State private var useVLCFallback = false
    @State private var visionSuspended = false
    @StateObject private var a500sProcessor = FrameProcessor()
    @StateObject private var cameraManager = CameraManager()

    private var selectedSource: CameraSourceChoice { CameraSourceChoice(rawValue: cameraSourceRaw) ?? .seventyMai }
    private var activeProcessor: FrameProcessor { selectedSource == .iPhone ? cameraManager.frameProcessor : a500sProcessor }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                header
                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06))
                    if !visionSuspended {
                        if selectedSource == .iPhone {
                            CameraPreview(session: cameraManager.session).clipShape(RoundedRectangle(cornerRadius: 18))
                        } else if useVLCFallback {
                            SeventyMaiPlayerView(urlString: CameraSource.seventyMaiURL, restartToken: restartToken, frameProcessor: a500sProcessor, statusText: $rtspStatus).clipShape(RoundedRectangle(cornerRadius: 18))
                        } else {
                            RootlessSeventyMaiPlayerView(urlString: CameraSource.seventyMaiURL, restartToken: restartToken, frameProcessor: a500sProcessor, statusText: $rtspStatus).clipShape(RoundedRectangle(cornerRadius: 18))
                        }
                    }
                    LaneGuideOverlay().clipShape(RoundedRectangle(cornerRadius: 18))
                    DASDetectionOverlay(detections: activeProcessor.dasDetections).clipShape(RoundedRectangle(cornerRadius: 18))
                }
                .frame(maxHeight: .infinity).clipped()

                HStack {
                    Text(activeProcessor.dasInferenceMS > 0 ? "YOLO READY · \(activeProcessor.dasDetections.count) objects" : "YOLO LOADING")
                    Spacer()
                    Text(activeProcessor.dasInferenceMS > 0 ? String(format: "%.0f ms", activeProcessor.dasInferenceMS) : "-- ms")
                }.font(.caption).foregroundStyle(.secondary)

                HStack(spacing: 16) {
                    Label("Sound", systemImage: "speaker.wave.2.fill")
                    Label("Vibration", systemImage: "iphone.radiowaves.left.and.right")
                    Spacer()
                    if selectedSource == .seventyMai { Button("RECONNECT") { restartA500S() } }
                }.font(.caption)

                Picker("Camera source", selection: $cameraSourceRaw) {
                    Text("70mai A500S").tag(CameraSourceChoice.seventyMai.rawValue)
                    Text("iPhone Rear").tag(CameraSourceChoice.iPhone.rawValue)
                }.pickerStyle(.segmented)
            }
            .padding().foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear { configureSource() }
        .onChange(of: cameraSourceRaw) { _ in configureSource() }
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
                Text(selectedSource == .seventyMai ? "70mai A500S · \(rtspStatus)" : "iPhone Rear · active").font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Text(riskText).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                .background(riskColor.opacity(0.85)).clipShape(Capsule())
        }
    }

    private var riskText: String {
        switch activeProcessor.dasRisk.level { case .clear: "CLEAR"; case .caution: "CAUTION"; case .warning: "WARNING" }
    }
    private var riskColor: Color {
        switch activeProcessor.dasRisk.level { case .clear: .green; case .caution: .orange; case .warning: .red }
    }

    private func configureSource() {
        visionSuspended = false
        if selectedSource == .iPhone { cameraManager.start(); useVLCFallback = false }
        else { cameraManager.stop(); restartA500S() }
    }
    private func restartA500S() {
        useVLCFallback = false; rtspStatus = "70MAI STARTING"; restartToken = UUID()
        let token = restartToken
        DispatchQueue.main.asyncAfter(deadline: .now() + 6) {
            guard selectedSource == .seventyMai, restartToken == token,
                  a500sProcessor.frameWidth == 0 || a500sProcessor.frameHeight == 0 else { return }
            rtspStatus = "70MAI VLC FALLBACK"; useVLCFallback = true
        }
    }
}

private struct DASDetectionOverlay: View {
    let detections: [ADASDetection]
    var body: some View {
        GeometryReader { geometry in
            ForEach(detections) { detection in
                let r = detection.boundingBox
                let rect = CGRect(x: r.minX * geometry.size.width, y: r.minY * geometry.size.height,
                                  width: r.width * geometry.size.width, height: r.height * geometry.size.height)
                ZStack(alignment: .topLeading) {
                    Rectangle().stroke(.yellow, lineWidth: 2)
                    Text("\(detection.label) \(Int(detection.confidence * 100))%")
                        .font(.caption2.bold()).padding(.horizontal, 4).padding(.vertical, 2)
                        .background(.yellow).foregroundStyle(.black)
                }.frame(width: max(rect.width, 1), height: max(rect.height, 1)).position(x: rect.midX, y: rect.midY)
            }
        }.allowsHitTesting(false)
    }
}

private struct LaneGuideOverlay: View {
    var body: some View {
        GeometryReader { g in
            Path { p in
                p.move(to: CGPoint(x:g.size.width*0.14,y:g.size.height*0.98)); p.addLine(to: CGPoint(x:g.size.width*0.43,y:g.size.height*0.48))
                p.move(to: CGPoint(x:g.size.width*0.86,y:g.size.height*0.98)); p.addLine(to: CGPoint(x:g.size.width*0.57,y:g.size.height*0.48))
            }.stroke(.yellow.opacity(0.9), style: StrokeStyle(lineWidth:4,lineCap:.round,dash:[12,10]))
        }.allowsHitTesting(false)
    }
}
