import SwiftUI
@preconcurrency import WebRTC

struct RemoteVideoView: NSViewRepresentable {
    let videoTrack: RTCVideoTrack

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> RTCMTLNSVideoView {
        let view = RTCMTLNSVideoView(frame: .zero)
        context.coordinator.update(track: videoTrack, renderer: view)
        return view
    }

    func updateNSView(_ nsView: RTCMTLNSVideoView, context: Context) {
        context.coordinator.update(track: videoTrack, renderer: nsView)
    }

    static func dismantleNSView(_ nsView: RTCMTLNSVideoView, coordinator: Coordinator) {
        coordinator.removeRenderer(nsView)
    }

    final class Coordinator {
        private var track: RTCVideoTrack?

        func update(track: RTCVideoTrack, renderer: RTCMTLNSVideoView) {
            guard self.track !== track else { return }
            self.track?.remove(renderer)
            track.add(renderer)
            self.track = track
        }

        func removeRenderer(_ renderer: RTCMTLNSVideoView) {
            track?.remove(renderer)
            track = nil
        }
    }
}
