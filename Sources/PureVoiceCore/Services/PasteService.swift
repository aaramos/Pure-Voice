import AppKit
import ApplicationServices
import Foundation

public final class PasteService: @unchecked Sendable {
    private let targetLock = NSLock()
    private var activationObserver: NSObjectProtocol?
    private var lastExternalTarget: FocusTarget?

    public init() {
        rememberFrontmostApplication()
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            self?.remember(application)
        }
    }

    deinit {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
    }

    public func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func captureFocus() -> FocusTarget? {
        if let target = focusTarget(from: NSWorkspace.shared.frontmostApplication) {
            storeLastExternalTarget(target)
            return target
        }

        targetLock.lock()
        defer { targetLock.unlock() }
        return lastExternalTarget
    }

    public func pasteOrCopy(_ text: String, originalTarget: FocusTarget?) -> PasteDeliveryResult {
        guard copyToPasteboard(text) else {
            return PasteDeliveryResult(status: .failed, fallbackReason: .clipboardUnavailable)
        }

        let target = originalTarget ?? captureFocus()
        guard let target else {
            return PasteDeliveryResult(status: .copied, fallbackReason: .targetUnavailable)
        }

        guard hasAccessibilityPermission(prompt: false) else {
            return PasteDeliveryResult(status: .copied, fallbackReason: .accessibilityPermissionMissing, target: target)
        }

        guard let targetApplication = runningApplication(for: target) else {
            return PasteDeliveryResult(status: .copied, fallbackReason: .targetUnavailable, target: target)
        }

        if !isFrontmost(targetApplication, matching: target) {
            targetApplication.activate(options: [.activateAllWindows])
        }

        guard waitForFrontmostApplication(matching: target) else {
            return PasteDeliveryResult(status: .copied, fallbackReason: .targetActivationFailed, target: target)
        }

        Thread.sleep(forTimeInterval: 0.12)
        guard postCommandV() else {
            return PasteDeliveryResult(status: .copied, fallbackReason: .pasteEventFailed, target: target)
        }

        return PasteDeliveryResult(status: .pasted, target: target)
    }

    private func rememberFrontmostApplication() {
        remember(NSWorkspace.shared.frontmostApplication)
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let target = focusTarget(from: application) else { return }
        storeLastExternalTarget(target)
    }

    private func focusTarget(from application: NSRunningApplication?) -> FocusTarget? {
        guard let app = application else { return nil }
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return nil
        }
        if app.bundleIdentifier == Bundle.main.bundleIdentifier {
            return nil
        }
        guard !app.isTerminated else { return nil }
        return FocusTarget(
            processIdentifier: app.processIdentifier,
            applicationName: app.localizedName,
            bundleIdentifier: app.bundleIdentifier
        )
    }

    private func storeLastExternalTarget(_ target: FocusTarget) {
        targetLock.lock()
        lastExternalTarget = target
        targetLock.unlock()
    }

    private func runningApplication(for target: FocusTarget) -> NSRunningApplication? {
        if let application = NSRunningApplication(processIdentifier: target.processIdentifier),
           !application.isTerminated {
            return application
        }

        guard let bundleIdentifier = target.bundleIdentifier else { return nil }
        return NSWorkspace.shared.runningApplications.first { application in
            application.bundleIdentifier == bundleIdentifier && !application.isTerminated
        }
    }

    private func waitForFrontmostApplication(matching target: FocusTarget) -> Bool {
        let deadline = Date().addingTimeInterval(1.5)
        while Date() < deadline {
            if isFrontmost(NSWorkspace.shared.frontmostApplication, matching: target) {
                return true
            }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(0.05))
        }
        return isFrontmost(NSWorkspace.shared.frontmostApplication, matching: target)
    }

    private func isFrontmost(_ application: NSRunningApplication?, matching target: FocusTarget) -> Bool {
        guard let application else { return false }
        if application.processIdentifier == target.processIdentifier {
            return true
        }
        guard let bundleIdentifier = target.bundleIdentifier else { return false }
        return application.bundleIdentifier == bundleIdentifier
    }

    private func postCommandV() -> Bool {
        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        guard let keyDown, let keyUp else { return false }
        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
        return true
    }

    @discardableResult
    public func copyToPasteboard(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        for _ in 0..<3 {
            pasteboard.clearContents()
            pasteboard.declareTypes([.string], owner: nil)
            if pasteboard.setString(text, forType: .string),
               pasteboard.string(forType: .string) == text {
                return true
            }
            Thread.sleep(forTimeInterval: 0.03)
        }

        return false
    }
}
