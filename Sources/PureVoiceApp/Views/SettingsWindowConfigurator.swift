import AppKit
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let view = NSView(frame: .zero)
        DispatchQueue.main.async {
            configure(window: view.window)
        }
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            configure(window: nsView.window)
        }
    }

    private func configure(window: NSWindow?) {
        guard let window else { return }

        window.styleMask.insert([.miniaturizable, .resizable])
        window.minSize = NSSize(width: 560, height: 520)
        window.collectionBehavior.insert(.fullScreenPrimary)

        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}
