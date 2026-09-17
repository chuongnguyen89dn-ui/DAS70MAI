import SwiftUI

struct ContentView: View {
    @State private var selection: CameraSelection = .iPhoneRearCamera
    @State private var rearCamera = RearCameraSource()

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            VStack(spacing: 16) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("DAS70MAI")
                            .font(.title2.bold())
                        Text(selection == .a500s ? "70mai A500S" : "iPhone Rear · Test")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                    Circle()
                        .fill(selection == .iPhoneRearCamera ? .green : .orange)
                        .frame(width: 10, height: 10)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.06))

                    if selection == .iPhoneRearCamera {
                        RearCameraPreview(session: rearCamera.session)
                            .clipShape(RoundedRectangle(cornerRadius: 18))
                    } else {
                        VStack(spacing: 10) {
                            Image(systemName: "video.fill")
                                .font(.system(size: 44))
                            Text("70mai A500S")
                                .font(.headline)
                            Text("RTSP integration is the next camera source")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxHeight: .infinity)

                CameraSourcePicker(selection: $selection)
            }
            .padding()
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
        .onAppear {
            if selection == .iPhoneRearCamera { rearCamera.start() }
        }
        .onChange(of: selection) { newValue in
            if newValue == .iPhoneRearCamera {
                rearCamera.start()
            } else {
                rearCamera.stop()
            }
        }
        .onDisappear { rearCamera.stop() }
    }
}
