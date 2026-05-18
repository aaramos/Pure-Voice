import AppKit
import SwiftUI

struct SettingsWindowConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        SettingsWindowConfigurationView(frame: .zero)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        DispatchQueue.main.async {
            Self.configure(window: nsView.window)
        }
    }

    static func configure(window: NSWindow?) {
        guard let window else { return }

        window.styleMask.insert([.miniaturizable, .resizable])
        window.minSize = NSSize(width: 560, height: 520)
        window.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.contentMinSize = NSSize(width: 560, height: 520)
        window.contentMaxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        window.collectionBehavior.insert(.fullScreenPrimary)

        window.standardWindowButton(.miniaturizeButton)?.isHidden = false
        window.standardWindowButton(.miniaturizeButton)?.isEnabled = true
        window.standardWindowButton(.zoomButton)?.isHidden = false
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}

private final class SettingsWindowConfigurationView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        configureNowAndSoon()
    }

    override func viewDidMoveToSuperview() {
        super.viewDidMoveToSuperview()
        configureNowAndSoon()
    }

    private func configureNowAndSoon() {
        SettingsWindowConfigurator.configure(window: window)
        DispatchQueue.main.async { [weak self] in
            SettingsWindowConfigurator.configure(window: self?.window)
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            SettingsWindowConfigurator.configure(window: self?.window)
        }
    }
}
