import SwiftUI

struct CameraSourcePicker: View {
    @Binding var selection: CameraSelection

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Camera source")
                .font(.caption)
                .foregroundStyle(.secondary)

            Picker("Camera source", selection: $selection) {
                Text("70mai A500S").tag(CameraSelection.a500s)
                Text("iPhone Rear").tag(CameraSelection.iPhoneRearCamera)
            }
            .pickerStyle(.segmented)
        }
        .accessibilityHint("Choose which camera supplies video to the ADAS pipeline")
    }
}
