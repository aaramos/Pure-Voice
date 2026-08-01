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
                .environment(\.colorScheme, .light)
        ))
        self.dismissAction = onDismiss

        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 860, height: 264),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        level = .statusBar
        isFloatingPanel = true
        becomesKeyOnlyIfNeeded = true
        isMovableByWindowBackground = false
        hasShadow = true
        isOpaque = false
        backgroundColor = .clear
        appearance = NSAppearance(named: .aqua)
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        hidesOnDeactivate = false

        let containerView = NSView(frame: contentView?.bounds ?? .zero)
        containerView.appearance = NSAppearance(named: .aqua)
        containerView.autoresizingMask = [.width, .height]
        containerView.wantsLayer = true
        containerView.layer?.backgroundColor = NSColor(calibratedWhite: 0.88, alpha: 0.98).cgColor
        containerView.layer?.cornerRadius = 42
        containerView.layer?.cornerCurve = .continuous
        containerView.layer?.masksToBounds = true
        containerView.layer?.borderWidth = 1
        containerView.layer?.borderColor = NSColor.black.withAlphaComponent(0.08).cgColor

        hostingView.translatesAutoresizingMaskIntoConstraints = false
        hostingView.wantsLayer = true
        hostingView.appearance = NSAppearance(named: .aqua)
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        containerView.addSubview(hostingView)
        contentView = containerView

        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: containerView.topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    func show(allowsUserDismissal: Bool, takesKeyFocus: Bool) {
        level = .statusBar
        reposition()
        if allowsUserDismissal {
            installDismissMonitorsIfNeeded()
        } else {
            removeDismissMonitors()
        }
        if takesKeyFocus {
            makeKeyAndOrderFront(nil)
        } else {
            if isKeyWindow {
                resignKey()
            }
            orderFrontRegardless()
        }
    }

    func reposition() {
        guard let screen = NSScreen.main ?? NSScreen.screens.first else { return }
        contentView?.layoutSubtreeIfNeeded()

        let width: CGFloat = 860
        let fittingHeight = hostingView.fittingSize.height
        let height = max(236, fittingHeight)
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

        let mouseMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown]
        if let globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: mouseMask, handler: { [weak self] event in
            Task { @MainActor [weak self] in
                self?.handleDismissEvent(event)
            }
        }) {
            eventMonitors.append(globalMonitor)
        }

        let localMask: NSEvent.EventTypeMask = [.leftMouseDown, .rightMouseDown, .keyDown]
        let localMonitor = NSEvent.addLocalMonitorForEvents(matching: localMask) { [weak self] event in
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
