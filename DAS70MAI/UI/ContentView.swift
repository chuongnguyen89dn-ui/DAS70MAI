import SwiftUI

struct ContentView: View {
    @State private var selection: CameraSelection = .iPhoneRearCamera
    @StateObject private var adas = ADASViewModel()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAS70MAI").font(.title2.bold())
                        Text(selection == .a500s ? "70mai A500S · \(a500sStatus)" : "iPhone Rear · Test")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(riskText).font(.caption.bold()).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(riskColor.opacity(0.85)).clipShape(Capsule())
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06))
                    if selection == .iPhoneRearCamera {
                        RearCameraPreview(session: adas.rearCamera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else if let frame = adas.a500sFrame {
                        Image(decorative: frame, scale: 1).resizable().scaledToFill()
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            ProgressView().tint(.white)
                            Text("70mai A500S").font(.headline)
                            Text(a500sStatus).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    DetectionOverlay(detections: adas.detections)
                        .clipShape(RoundedRectangle(cornerRadius: 18))
                }.frame(maxHeight: .infinity).clipped()

                HStack {
                    Text(adas.inferenceActive ? "YOLO active" : "YOLO loading")
                    Spacer()
                    Text(String(format: "%.0f ms · age %.0f ms · drop %llu", adas.inferenceMilliseconds, adas.frameAgeMilliseconds, adas.replacedFrames))
                }.font(.caption).foregroundStyle(.secondary)

                CameraSourcePicker(selection: $selection)
            }.padding().foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear { if selection == .iPhoneRearCamera { adas.startRearCamera() } else { adas.startA500S() } }
        .onChange(of: selection) { newValue in
            if newValue == .iPhoneRearCamera { adas.startRearCamera() } else { adas.startA500S() }
        }
        .onDisappear { adas.stopRearCamera(); adas.stopA500S() }
    }

    private var a500sStatus: String {
        switch adas.a500sState {
        case .idle: "idle"
        case .connecting: "connecting RTSP"
        case .streaming: "RTSP connected"
        case .failed(let message): "stream error: \(message)"
        }
    }
    private var riskText: String {
        switch adas.risk.level { case .clear: "CLEAR"; case .caution: "CAUTION"; case .warning: "WARNING" }
    }
    private var riskColor: Color {
        switch adas.risk.level { case .clear: .green; case .caution: .orange; case .warning: .red }
    }
}
