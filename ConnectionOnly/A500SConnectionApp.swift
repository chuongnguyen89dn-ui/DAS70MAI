import SwiftUI
import VLCKit

@main
struct DAS70MAIApp: App {
    var body: some Scene {
        WindowGroup { A500SConnectionView() }
    }
}

struct A500SConnectionView: View {
    var body: some View {
        ZStack(alignment: .top) {
            A500SVLCView(url: URL(string: "rtsp://192.168.0.1/00000000")!)
                .ignoresSafeArea()
            Text("70mai A500S • rtsp://192.168.0.1/00000000")
                .font(.caption.bold())
                .padding(8)
                .background(.black.opacity(0.65))
                .foregroundStyle(.white)
                .clipShape(Capsule())
                .padding(.top, 8)
        }
        .background(Color.black)
    }
}

struct A500SVLCView: UIViewRepresentable {
    let url: URL

    func makeCoordinator() -> Coordinator { Coordinator(url: url) }

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .black
        context.coordinator.attach(to: view)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.attach(to: uiView)
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.stop()
    }

    final class Coordinator: NSObject {
        private let player = VLCMediaPlayer()
        private let url: URL
        private weak var attachedView: UIView?

        init(url: URL) { self.url = url }

        func attach(to view: UIView) {
            guard attachedView !== view else { return }
            attachedView = view
            player.drawable = view
            guard let media = VLCMedia(url: url) else { return }
            media.addOption(":network-caching=180")
            media.addOption(":live-caching=180")
            media.addOption(":clock-jitter=0")
            media.addOption(":clock-synchro=0")
            media.addOption(":drop-late-frames")
            media.addOption(":skip-frames")
            player.media = media
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) { [weak self] in
                self?.player.play()
            }
        }

        func stop() { player.stop() }
    }
}
