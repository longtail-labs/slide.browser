import AppKit
import SwiftUI

/// Controls visibility of the macOS window traffic light buttons (close, minimize, zoom).
/// Place this view somewhere in the hierarchy so it can access the hosting NSWindow.
struct WindowControlsVisibility: NSViewRepresentable {
    let isVisible: Bool

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { updateWindowButtons(for: view, isVisible: isVisible) }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async { updateWindowButtons(for: nsView, isVisible: isVisible) }
    }

    private func updateWindowButtons(for view: NSView, isVisible: Bool) {
        guard let window = view.window else { return }
        window.standardWindowButton(.closeButton)?.isHidden = !isVisible
        window.standardWindowButton(.miniaturizeButton)?.isHidden = !isVisible
        window.standardWindowButton(.zoomButton)?.isHidden = !isVisible
    }
}

