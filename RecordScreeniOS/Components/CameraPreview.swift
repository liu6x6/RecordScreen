import SwiftUI
@preconcurrency import WebRTC

struct CameraPreview: UIViewRepresentable {
    let videoTrack: RTCVideoTrack?

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> RTCMTLVideoView {
        let view = RTCMTLVideoView(frame: .zero)
        view.videoContentMode = .scaleAspectFill
        context.coordinator.update(track: videoTrack, renderer: view)
        return view
    }

    func updateUIView(_ uiView: RTCMTLVideoView, context: Context) {
        context.coordinator.update(track: videoTrack, renderer: uiView)
    }

    static func dismantleUIView(_ uiView: RTCMTLVideoView, coordinator: Coordinator) {
        coordinator.removeRenderer(uiView)
    }

    final class Coordinator {
        private var track: RTCVideoTrack?

        func update(track: RTCVideoTrack?, renderer: RTCMTLVideoView) {
            guard self.track !== track else { return }
            self.track?.remove(renderer)
            track?.add(renderer)
            self.track = track
        }

        func removeRenderer(_ renderer: RTCMTLVideoView) {
            track?.remove(renderer)
            track = nil
        }
    }
}
