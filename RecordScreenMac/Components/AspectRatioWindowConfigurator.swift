import AppKit
import SwiftUI

struct AspectRatioWindowConfigurator: NSViewRepresentable {
    let contentSize: CGSize

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        configureWindow(from: view, coordinator: context.coordinator)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        configureWindow(from: nsView, coordinator: context.coordinator)
    }

    private func configureWindow(from view: NSView, coordinator: Coordinator) {
        guard contentSize.width > 0, contentSize.height > 0 else { return }
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            let size = NSSize(width: contentSize.width, height: contentSize.height)
            window.contentAspectRatio = size
            if coordinator.lastContentSize != size {
                window.setContentSize(size)
                coordinator.lastContentSize = size
            }
        }
    }

    final class Coordinator {
        var lastContentSize: NSSize?
    }
}
