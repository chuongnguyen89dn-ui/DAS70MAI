import SwiftUI

struct ContentView: View {
    @State private var selection: CameraSelection = .iPhoneRearCamera

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
                        .fill(.orange)
                        .frame(width: 10, height: 10)
                }

                ZStack {
                    RoundedRectangle(cornerRadius: 18)
                        .fill(Color.white.opacity(0.06))
                    VStack(spacing: 10) {
                        Image(systemName: selection == .a500s ? "video.fill" : "iphone.gen3")
                            .font(.system(size: 44))
                        Text(selection == .a500s ? "A500S stream" : "Rear camera test")
                            .font(.headline)
                        Text("Video preview will use the selected source only")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxHeight: .infinity)

                CameraSourcePicker(selection: $selection)
            }
            .padding()
            .foregroundStyle(.white)
        }
        .preferredColorScheme(.dark)
    }
}
