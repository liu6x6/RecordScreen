@preconcurrency import AVFoundation
import Foundation

typealias VideoFrameHandler = (CVPixelBuffer, CMTime) -> Void

final class VideoFrameDelivery: @unchecked Sendable {
    private let lock = NSLock()
    private var handler: VideoFrameHandler?

    func setHandler(_ handler: VideoFrameHandler?) {
        lock.lock()
        self.handler = handler
        lock.unlock()
    }

    func deliver(pixelBuffer: CVPixelBuffer, presentationTime: CMTime) {
        lock.lock()
        let handler = self.handler
        lock.unlock()
        handler?(pixelBuffer, presentationTime)
    }
}
