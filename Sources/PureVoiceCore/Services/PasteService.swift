import AppKit
import ApplicationServices
import Foundation

public final class PasteService: @unchecked Sendable {
    public init() {}

    public func hasAccessibilityPermission(prompt: Bool) -> Bool {
        let options = ["AXTrustedCheckOptionPrompt": prompt] as CFDictionary
        return AXIsProcessTrustedWithOptions(options)
    }

    public func captureFocus() -> FocusTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            return nil
        }
        return FocusTarget(
            processIdentifier: app.processIdentifier,
            applicationName: app.localizedName
        )
    }

    public func pasteOrCopy(_ text: String, originalTarget: FocusTarget?) -> PasteStatus {
        guard copyToPasteboard(text) else {
            return .failed
        }

        let accessibilityAllowed = hasAccessibilityPermission(prompt: false)
        guard
            accessibilityAllowed,
            let originalTarget,
            let current = NSWorkspace.shared.frontmostApplication,
            current.processIdentifier == originalTarget.processIdentifier
        else {
            return .copied
        }

        let source = CGEventSource(stateID: .combinedSessionState)
        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false)
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand
        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
        return .pasted
    }

    @discardableResult
    public func copyToPasteboard(_ text: String) -> Bool {
        guard !text.isEmpty else { return false }

        let pasteboard = NSPasteboard.general
        for _ in 0..<3 {
            pasteboard.clearContents()
            if pasteboard.setString(text, forType: .string),
               pasteboard.string(forType: .string) == text {
                return true
            }
            Thread.sleep(forTimeInterval: 0.03)
        }

        return false
    }
}
