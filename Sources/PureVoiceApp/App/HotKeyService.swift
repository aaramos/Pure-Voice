import AppKit
import Foundation

final class HotKeyService: @unchecked Sendable {
    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var action: (() -> Void)?

    func start(action: @escaping () -> Void) {
        self.action = action
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.matchesHotKey(event) == true else { return }
            DispatchQueue.main.async {
                self?.action?()
            }
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.matchesHotKey(event) == true else { return event }
            self?.action?()
            return nil
        }
    }

    func stop() {
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
    }

    private func matchesHotKey(_ event: NSEvent) -> Bool {
        let relevant = event.modifierFlags.intersection([.control, .option, .command, .shift])
        return event.keyCode == 49 && relevant == [.control, .option]
    }
}
