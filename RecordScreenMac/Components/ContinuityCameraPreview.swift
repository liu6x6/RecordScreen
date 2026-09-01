@preconcurrency import AVFoundation
import SwiftUI

struct ContinuityCameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> ContinuityPreviewView {
        let view = ContinuityPreviewView()
        view.previewLayer.session = session
        return view
    }

    func updateNSView(_ nsView: ContinuityPreviewView, context: Context) {
        nsView.previewLayer.session = session
    }
}

final class ContinuityPreviewView: NSView {
    let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        previewLayer.videoGravity = .resizeAspect
        layer?.addSublayer(previewLayer)
    }

    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        previewLayer.frame = bounds
    }
}
