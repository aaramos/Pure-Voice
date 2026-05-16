import AppKit
import SwiftUI

@MainActor
final class RecordingStatusPanel: NSPanel {
    private let hostingView: NSHostingView<AnyView>
    private let dismissAction: @MainActor () -> Void
    private var eventMonitors: [Any] = []

    init(state: AppState, onDismiss: @escaping @MainActor () -> Void) {
        self.hostingView = NSHostingView(rootView: AnyView(
            StatusModalView(state: state)
                .environment(\.colorScheme, .dark)
        ))
        self.dismissAction = onDismiss

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 176),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .floating
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .darkAqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]

        let effectView = NSVisualEffectView(frame: contentView?.bounds ?? .zero)
        effectView.material = .hudWindow
        effectView.blendingMode = .behindWindow
        effectView.state = .active
        effectView.appearance = NSAppearance(named: .darkAqua)
        effectView.autoresizingMask = [.width, .height]
        effectView.wantsLayer = true
        effectView.layer?.cornerRadius = 22
        effectView.layer?.cornerCurve = .continuous
        effectView.layer?.masksToBounds = true

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.appearance = NSAppearance(named: .darkAqua)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        effectView.addSubview(hostingView)
        contentView = effectView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: effectView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: effectView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: effectView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: effectView.bottomAnchor)
        ])
    }

    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    func show() {
        reposition()
        installDismissMonitorsIfNeeded()
        orderFrontRegardless()
    }

    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        contentView?.layoutSubtreeIfNeeded()

        let width: CGFloat = 420
        let fittingHeight = hostingView.fittingSize.height
        let height = max(148, fittingHeight)
        let visibleFrame = screen.visibleFrame
        let originX = visibleFrame.midX - width / 2
        let centerY = visibleFrame.maxY - visibleFrame.height * 0.45
        let originY = centerY - height / 2

        setFrame(NSRect(x: originX, y: originY, width: width, height: height), display: true)
    }

    override func orderOut(_ sender: Any?) {
        removeDismissMonitors()
        super.orderOut(sender)
    }

    private func installDismissMonitorsIfNeeded() {
        guard eventMonitors.isEmpty else { return }

        let mask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDismissEvent(event)
            }
        }) {
            eventMonitors.append(globalMonitor)
        }

        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: mask) { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDismissEvent(event)
            }
            return event
        }

        if let localMonitor {
            eventMonitors.append(localMonitor)
        }
    }

    private func removeDismissMonitors() {
        eventMonitors.forEach(NSEvent.removeMonitor)
        eventMonitors.removeAll()
    }

    private func handleDismissEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53 {
            dismissAction()
            return
        }

        guard event.type == .leftMouseDown || event.type == .rightMouseDown else { return }
        if !frame.contains(NSEvent.mouseLocation) {
            dismissAction()
        }
    }
}
