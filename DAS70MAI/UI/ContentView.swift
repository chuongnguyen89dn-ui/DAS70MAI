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
                        Text(selection == .a500s ? "70mai A500S" : "iPhone Rear · Test")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Text(riskText)
                        .font(.caption.bold())
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(riskColor.opacity(0.85))
                        .clipShape(Capsule())
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18).fill(Color.white.opacity(0.06))
                    if selection == .iPhoneRearCamera {
                        RearCameraPreview(session: adas.rearCamera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                        DetectionOverlay(detections: adas.detections)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill").font(.system(size: 44))
                            Text("70mai A500S").font(.headline)
                            Text("RTSP integration is the next camera source")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                HStack {
                    Text(adas.inferenceActive ? "YOLO active" : "YOLO loading")
                    Spacer()
                    Text("\(adas.detections.count) road objects")
                }
                .font(.caption).foregroundStyle(.secondary)

                CameraSourcePicker(selection: $selection)
            }
            .padding().foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear { if selection == .iPhoneRearCamera { adas.startRearCamera() } }
        .onChange(of: selection) { newValue in
            if newValue == .iPhoneRearCamera { adas.startRearCamera() }
            else { adas.stopRearCamera() }
        }
        .onDisappear { adas.stopRearCamera() }
    }

    private var riskText: String {
        switch adas.risk.level {
        case .clear: "CLEAR"
        case .caution: "CAUTION"
        case .warning: "WARNING"
        }
    }

    private var riskColor: Color {
        switch adas.risk.level {
        case .clear: .green
        case .caution: .orange
        case .warning: .red
        }
    }
}
