import AppKit
import Foundation

final class HotKeyService: @unchecked Sendable {
    private enum KeyCode {
        static let rightCommand: UInt16 = 54
        static let rightOption: UInt16 = 61
    }

    private var globalMonitor: Any?
    private var localMonitor: Any?
    private var onStart: (() -> Void)?
    private var onStop: (() -> Void)?
    private var rightCommandDown = false
    private var rightOptionDown = false
    private var startChordConsumed = false
    private var rightOptionPressConsumed = false

    func start(onStart: @escaping () -> Void, onStop: @escaping () -> Void) {
        self.onStart = onStart
        self.onStop = onStop
        stop()

        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
        }

        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.handle(event)
            return event
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
        resetState()
    }

    deinit {
        stop()
    }

    private func handle(_ event: NSEvent) {
        switch event.keyCode {
        case KeyCode.rightCommand:
            rightCommandDown = event.modifierFlags.contains(.command)
        case KeyCode.rightOption:
            rightOptionDown = event.modifierFlags.contains(.option)
            if !rightOptionDown {
                rightOptionPressConsumed = false
                startChordConsumed = false
                return
            }
        default:
            return
        }

        if rightCommandDown && rightOptionDown {
            guard !startChordConsumed else { return }
            startChordConsumed = true
            rightOptionPressConsumed = true
            DispatchQueue.main.async { [weak self] in
                self?.onStart?()
            }
            return
        }

        if rightOptionDown && !rightCommandDown && !rightOptionPressConsumed {
            rightOptionPressConsumed = true
            DispatchQueue.main.async { [weak self] in
                self?.onStop?()
            }
        }
    }

    private func resetState() {
        rightCommandDown = false
        rightOptionDown = false
        startChordConsumed = false
        rightOptionPressConsumed = false
    }
}
