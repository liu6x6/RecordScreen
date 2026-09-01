@preconcurrency import AVFoundation
import Foundation
@preconcurrency import WebRTC

final class WebRTCRecordingRenderer: NSObject, RTCVideoRenderer {
    private let frameDelivery = VideoFrameDelivery()
    private var unsupportedFrameCount = 0

    func setFrameHandler(_ handler: VideoFrameHandler?) {
        frameDelivery.setHandler(handler)
    }

    func setSize(_ size: CGSize) {}

    func renderFrame(_ frame: RTCVideoFrame?) {
        guard let frame else { return }
        guard let buffer = frame.buffer as? RTCCVPixelBuffer else {
            unsupportedFrameCount += 1
            if unsupportedFrameCount == 1 || unsupportedFrameCount.isMultiple(of: 60) {
                AppLog.recording.notice(
                    "Dropped \(self.unsupportedFrameCount, privacy: .public) WebRTC frame(s) without a CVPixelBuffer."
                )
            }
            return
        }

        let timestamp = frame.timeStampNs
        guard timestamp >= 0 else {
            AppLog.recording.error("Dropped WebRTC frame with an invalid negative timestamp.")
            return
        }

        frameDelivery.deliver(
            pixelBuffer: buffer.pixelBuffer,
            presentationTime: CMTime(value: timestamp, timescale: 1_000_000_000)
        )
    }
}
