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
        copyToPasteboard(text)

        guard
            hasAccessibilityPermission(prompt: false),
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

    public func copyToPasteboard(_ text: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
    }
}
