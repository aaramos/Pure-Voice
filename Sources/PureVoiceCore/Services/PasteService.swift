import AppKit
import ApplicationServices
import Foundation
import OSLog

private let pasteLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.adrian.purevoice",
    category: "PasteDelivery"
)

public struct TargetAppProfile: Equatable, Sendable {
    public var bundleIdentifier: String?
    public var hasWebAreaAncestor: Bool

    public init(bundleIdentifier: String?, hasWebAreaAncestor: Bool = false) {
        self.bundleIdentifier = bundleIdentifier
        self.hasWebAreaAncestor = hasWebAreaAncestor
    }

    public var isElectronTarget: Bool {
        Self.isElectronLike(bundleIdentifier: bundleIdentifier, hasWebAreaAncestor: hasWebAreaAncestor)
    }

    public static func isElectronLike(bundleIdentifier: String?, hasWebAreaAncestor: Bool = false) -> Bool {
        if hasWebAreaAncestor {
            return true
        }

        guard let bundleIdentifier else { return false }
        let exactMatches: Set<String> = [
            "com.openai.codex",
            "com.anthropic.claudefordesktop",
            "com.github.GitHubClient",
            "com.tinyspeck.slackmacgap",
            "com.microsoft.VSCode",
            "com.anysphere.cursor"
        ]
        if exactMatches.contains(bundleIdentifier) {
            return true
        }

        return bundleIdentifier.hasPrefix("com.todesktop.")
            || bundleIdentifier.hasPrefix("com.electron.")
    }
}

public struct PasteDeliveryDiagnostics: Codable, Equatable, Sendable {
    public var bundleID: String?
    public var pid: Int32?
    public var appName: String?
    public var axTrusted: Bool
    public var focusedRole: String?
    public var focusedSubrole: String?
    public var focusedIdentifier: String?
    public var focusedTitle: String?
    public var isElectronTarget: Bool
    public var axValueReadable: Bool
    public var axValueSettable: Bool
    public var axWriteResultCode: Int?
    public var pasteboardChangeCountBefore: Int
    public var pasteboardChangeCountAfter: Int
    public var cmdVPosted: Bool
    public var cmdVRoute: String?
    public var verifiedValueChanged: Bool?
    public var finalStatus: PasteDeliveryStatus

    public init(
        bundleID: String? = nil,
        pid: Int32? = nil,
        appName: String? = nil,
        axTrusted: Bool = false,
        focusedRole: String? = nil,
        focusedSubrole: String? = nil,
        focusedIdentifier: String? = nil,
        focusedTitle: String? = nil,
        isElectronTarget: Bool = false,
        axValueReadable: Bool = false,
        axValueSettable: Bool = false,
        axWriteResultCode: Int? = nil,
        pasteboardChangeCountBefore: Int = 0,
        pasteboardChangeCountAfter: Int = 0,
        cmdVPosted: Bool = false,
        cmdVRoute: String? = nil,
        verifiedValueChanged: Bool? = nil,
        finalStatus: PasteDeliveryStatus = .copiedOnly
    ) {
        self.bundleID = bundleID
        self.pid = pid
        self.appName = appName
        self.axTrusted = axTrusted
        self.focusedRole = focusedRole
        self.focusedSubrole = focusedSubrole
        self.focusedIdentifier = focusedIdentifier
        self.focusedTitle = focusedTitle
        self.isElectronTarget = isElectronTarget
        self.axValueReadable = axValueReadable
        self.axValueSettable = axValueSettable
        self.axWriteResultCode = axWriteResultCode
        self.pasteboardChangeCountBefore = pasteboardChangeCountBefore
        self.pasteboardChangeCountAfter = pasteboardChangeCountAfter
        self.cmdVPosted = cmdVPosted
        self.cmdVRoute = cmdVRoute
        self.verifiedValueChanged = verifiedValueChanged
        self.finalStatus = finalStatus
    }

    public var jsonString: String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        guard let data = try? encoder.encode(self),
              let value = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return value
    }
}

private struct PasteTargetSnapshot {
    var focusTarget: FocusTarget
    var applicationElement: AXUIElement?
    var windowElement: AXUIElement?
    var focusedElement: AXUIElement?
    var focusedRole: String?
    var focusedSubrole: String?
    var focusedIdentifier: String?
    var focusedTitle: String?
    var hasWebAreaAncestor: Bool
}

public final class PasteService: @unchecked Sendable {
    private let targetLock = NSLock()
    private var activationObserver: NSObjectProtocol?
    private var lastTarget: PasteTargetSnapshot?

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
        guard let application = NSWorkspace.shared.frontmostApplication,
              let snapshot = makeSnapshot(from: application) else {
            targetLock.lock()
            defer { targetLock.unlock() }
            return lastTarget?.focusTarget
        }

        store(snapshot)
        return snapshot.focusTarget
    }

    public func pasteOrCopy(_ text: String, originalTarget: FocusTarget?) -> PasteDeliveryResult {
        var diagnostics = PasteDeliveryDiagnostics()
        let pasteboard = NSPasteboard.general
        diagnostics.pasteboardChangeCountBefore = pasteboard.changeCount

        let copied = copyToPasteboard(text)
        diagnostics.pasteboardChangeCountAfter = pasteboard.changeCount

        let target = snapshot(matching: originalTarget)
        if let focusTarget = target?.focusTarget {
            diagnostics.bundleID = focusTarget.bundleIdentifier
            diagnostics.pid = focusTarget.processIdentifier
            diagnostics.appName = focusTarget.applicationName
        }

        guard copied else {
            return finish(.copiedOnly, target: target?.focusTarget, diagnostics: diagnostics)
        }

        guard let target else {
            return finish(.focusedElementUnavailable, target: nil, diagnostics: diagnostics)
        }

        diagnostics.focusedRole = target.focusedRole
        diagnostics.focusedSubrole = target.focusedSubrole
        diagnostics.focusedIdentifier = target.focusedIdentifier
        diagnostics.focusedTitle = target.focusedTitle

        let profile = TargetAppProfile(
            bundleIdentifier: target.focusTarget.bundleIdentifier,
            hasWebAreaAncestor: target.hasWebAreaAncestor
        )
        diagnostics.isElectronTarget = profile.isElectronTarget

        let axTrusted = hasAccessibilityPermission(prompt: false)
        diagnostics.axTrusted = axTrusted

        guard axTrusted || profile.isElectronTarget else {
            return finish(.accessibilityDenied, target: target.focusTarget, diagnostics: diagnostics)
        }

        if axTrusted,
           !profile.isElectronTarget,
           let focusedElement = target.focusedElement {
            let beforeValue = valueString(focusedElement)
            diagnostics.axValueReadable = beforeValue != nil
            diagnostics.axValueSettable = isAttributeSettable(focusedElement, attribute: kAXValueAttribute as CFString)

            let axStatus = writeWithAX(text, to: focusedElement)
            diagnostics.axWriteResultCode = Int(axStatus.rawValue)
            if axStatus == .success {
                let afterValue = valueString(focusedElement)
                let changed = valueChanged(from: beforeValue, to: afterValue, insertedText: text)
                diagnostics.verifiedValueChanged = changed
                if changed == true {
                    return finish(.directAXInserted, target: target.focusTarget, diagnostics: diagnostics)
                }
            }
        }

        hidePureVoiceWindows()

        guard let targetApplication = runningApplication(for: target.focusTarget) else {
            return finish(.targetActivationFailed, target: target.focusTarget, diagnostics: diagnostics)
        }

        guard targetApplication.activate(options: []) else {
            return finish(.targetActivationFailed, target: target.focusTarget, diagnostics: diagnostics)
        }
        if axTrusted, let windowElement = target.windowElement {
            AXUIElementPerformAction(windowElement, kAXRaiseAction as CFString)
        }
        if axTrusted,
           let applicationElement = target.applicationElement,
           let focusedElement = target.focusedElement {
            AXUIElementSetAttributeValue(
                applicationElement,
                kAXFocusedUIElementAttribute as CFString,
                focusedElement
            )
        }

        Thread.sleep(forTimeInterval: 0.08)
        guard waitForFrontmostApplication(matching: target.focusTarget, timeout: 2.0) else {
            return finish(.targetActivationFailed, target: target.focusTarget, diagnostics: diagnostics)
        }

        let valueBeforePaste = axTrusted ? readableFocusedValue(for: target) : nil
        postCommandV()
        diagnostics.cmdVPosted = true
        diagnostics.cmdVRoute = "hidEventTap"

        guard axTrusted else {
            diagnostics.verifiedValueChanged = nil
            return finish(.pasteEventSentUnconfirmed, target: target.focusTarget, diagnostics: diagnostics)
        }

        let hidVerification = verifyValueChanged(
            for: target,
            previousValue: valueBeforePaste,
            insertedText: text
        )
        diagnostics.axValueReadable = diagnostics.axValueReadable || hidVerification.readable
        diagnostics.verifiedValueChanged = hidVerification.changed

        switch hidVerification.changed {
        case true:
            return finish(.pasteEventConfirmed, target: target.focusTarget, diagnostics: diagnostics)
        case nil:
            return finish(.pasteEventSentUnconfirmed, target: target.focusTarget, diagnostics: diagnostics)
        case false:
            break
        }

        guard runAppleScriptPaste(bundleIdentifier: target.focusTarget.bundleIdentifier) else {
            return finish(.targetDidNotAcceptPaste, target: target.focusTarget, diagnostics: diagnostics)
        }

        diagnostics.cmdVRoute = "appleScript"
        let appleScriptVerification = verifyValueChanged(
            for: target,
            previousValue: valueBeforePaste,
            insertedText: text
        )
        diagnostics.axValueReadable = diagnostics.axValueReadable || appleScriptVerification.readable
        diagnostics.verifiedValueChanged = appleScriptVerification.changed

        switch appleScriptVerification.changed {
        case true:
            return finish(.pasteEventConfirmed, target: target.focusTarget, diagnostics: diagnostics)
        case nil:
            return finish(.pasteEventSentUnconfirmed, target: target.focusTarget, diagnostics: diagnostics)
        case false:
            return finish(.targetDidNotAcceptPaste, target: target.focusTarget, diagnostics: diagnostics)
        }
    }

    private func finish(
        _ status: PasteDeliveryStatus,
        target: FocusTarget?,
        diagnostics: PasteDeliveryDiagnostics
    ) -> PasteDeliveryResult {
        var diagnostics = diagnostics
        diagnostics.finalStatus = status
        let json = diagnostics.jsonString
        pasteLogger.info("\(json, privacy: .public)")
        return PasteDeliveryResult(
            status: status,
            target: target,
            diagnosticJSON: json
        )
    }

    private func rememberFrontmostApplication() {
        remember(NSWorkspace.shared.frontmostApplication)
    }

    private func remember(_ application: NSRunningApplication?) {
        guard let application,
              let snapshot = makeSnapshot(from: application) else { return }
        store(snapshot)
    }

    private func makeSnapshot(from application: NSRunningApplication) -> PasteTargetSnapshot? {
        guard let focusTarget = focusTarget(from: application) else { return nil }

        let applicationElement = AXUIElementCreateApplication(application.processIdentifier)
        let focusedElement = focusedElement(from: applicationElement) ?? focusedElementFromSystem(matching: focusTarget)
        let windowElement = focusedWindow(from: applicationElement)

        return PasteTargetSnapshot(
            focusTarget: focusTarget,
            applicationElement: applicationElement,
            windowElement: windowElement,
            focusedElement: focusedElement,
            focusedRole: focusedElement.flatMap { stringAttribute($0, kAXRoleAttribute as CFString) },
            focusedSubrole: focusedElement.flatMap { stringAttribute($0, kAXSubroleAttribute as CFString) },
            focusedIdentifier: focusedElement.flatMap { stringAttribute($0, kAXIdentifierAttribute as CFString) },
            focusedTitle: focusedElement.flatMap { stringAttribute($0, kAXTitleAttribute as CFString) },
            hasWebAreaAncestor: focusedElement.map(hasWebAreaAncestor) ?? false
        )
    }

    private func store(_ target: PasteTargetSnapshot) {
        targetLock.lock()
        lastTarget = target
        targetLock.unlock()
    }

    private func snapshot(matching target: FocusTarget?) -> PasteTargetSnapshot? {
        targetLock.lock()
        let snapshot = lastTarget
        targetLock.unlock()

        guard let target else { return snapshot }
        if snapshot?.focusTarget == target {
            return snapshot
        }

        guard let application = runningApplication(for: target) else { return nil }
        return makeSnapshot(from: application)
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

    private func waitForFrontmostApplication(matching target: FocusTarget, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
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

    private func focusedElement(from applicationElement: AXUIElement) -> AXUIElement? {
        var rawElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedUIElementAttribute as CFString,
            &rawElement
        ) == .success,
              let rawElement else {
            return nil
        }

        return (rawElement as! AXUIElement)
    }

    private func focusedWindow(from applicationElement: AXUIElement) -> AXUIElement? {
        var rawWindow: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            applicationElement,
            kAXFocusedWindowAttribute as CFString,
            &rawWindow
        ) == .success,
              let rawWindow else {
            return nil
        }

        return (rawWindow as! AXUIElement)
    }

    private func focusedElementFromSystem(matching target: FocusTarget) -> AXUIElement? {
        let systemWideElement = AXUIElementCreateSystemWide()
        var rawElement: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            systemWideElement,
            kAXFocusedUIElementAttribute as CFString,
            &rawElement
        ) == .success,
              let rawElement else {
            return nil
        }

        let element = rawElement as! AXUIElement
        guard elementMatches(element, target: target) else { return nil }
        return element
    }

    private func elementMatches(_ element: AXUIElement, target: FocusTarget) -> Bool {
        var pid: pid_t = 0
        guard AXUIElementGetPid(element, &pid) == .success else { return false }
        if pid == target.processIdentifier {
            return true
        }

        guard let application = NSRunningApplication(processIdentifier: pid) else { return false }
        return isFrontmost(application, matching: target)
    }

    private func writeWithAX(_ text: String, to element: AXUIElement) -> AXError {
        let selectedTextStatus = AXUIElementSetAttributeValue(
            element,
            kAXSelectedTextAttribute as CFString,
            text as CFTypeRef
        )
        if selectedTextStatus == .success {
            return selectedTextStatus
        }

        let currentValue = valueString(element) ?? ""
        guard let selectedRange = selectedTextRange(in: element),
              let nextValue = Self.replacingSelectedText(
                in: currentValue,
                with: text,
                selectedRange: selectedRange
              ) else {
            return selectedTextStatus
        }

        let valueStatus = AXUIElementSetAttributeValue(
            element,
            kAXValueAttribute as CFString,
            nextValue as CFTypeRef
        )
        if valueStatus == .success {
            var insertionRange = CFRange(location: selectedRange.location + (text as NSString).length, length: 0)
            if let axRange = AXValueCreate(.cfRange, &insertionRange) {
                AXUIElementSetAttributeValue(element, kAXSelectedTextRangeAttribute as CFString, axRange)
            }
        }
        return valueStatus
    }

    private func readableFocusedValue(for target: PasteTargetSnapshot) -> String? {
        if let focusedElement = focusedElement(from: target.applicationElement ?? AXUIElementCreateApplication(target.focusTarget.processIdentifier)) {
            return valueString(focusedElement)
        }
        if let focusedElement = target.focusedElement {
            return valueString(focusedElement)
        }
        return nil
    }

    private func verifyValueChanged(
        for target: PasteTargetSnapshot,
        previousValue: String?,
        insertedText: String
    ) -> (changed: Bool?, readable: Bool) {
        for _ in 0..<4 {
            Thread.sleep(forTimeInterval: 0.1)
            let nextValue = readableFocusedValue(for: target)
            if let nextValue {
                return (valueChanged(from: previousValue, to: nextValue, insertedText: insertedText), true)
            }
        }
        return (nil, false)
    }

    private func valueChanged(from before: String?, to after: String?, insertedText: String) -> Bool? {
        guard let after else { return nil }
        guard let before else {
            return after.localizedCaseInsensitiveContains(insertedText)
        }

        if after == before {
            return false
        }
        if after.localizedCaseInsensitiveContains(insertedText) {
            return true
        }

        let expectedGrowth = max(1, min(insertedText.count, 12))
        return after.count >= before.count + expectedGrowth
    }

    private func valueString(_ element: AXUIElement) -> String? {
        stringAttribute(element, kAXValueAttribute as CFString)
    }

    private func stringAttribute(_ element: AXUIElement, _ attribute: CFString) -> String? {
        var rawValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute, &rawValue) == .success,
              let rawValue else {
            return nil
        }

        return rawValue as? String
    }

    private func isAttributeSettable(_ element: AXUIElement, attribute: CFString) -> Bool {
        var settable = DarwinBoolean(false)
        guard AXUIElementIsAttributeSettable(element, attribute, &settable) == .success else {
            return false
        }
        return settable.boolValue
    }

    private func selectedTextRange(in element: AXUIElement) -> CFRange? {
        var rawRange: CFTypeRef?
        guard AXUIElementCopyAttributeValue(
            element,
            kAXSelectedTextRangeAttribute as CFString,
            &rawRange
        ) == .success,
              let rawRange else {
            return nil
        }

        let axRange = rawRange as! AXValue
        var range = CFRange(location: 0, length: 0)
        guard AXValueGetValue(axRange, .cfRange, &range) else { return nil }
        return range
    }

    private func hasWebAreaAncestor(_ element: AXUIElement) -> Bool {
        var current: AXUIElement? = element
        for _ in 0..<12 {
            guard let element = current else { return false }
            if stringAttribute(element, kAXRoleAttribute as CFString) == "AXWebArea" {
                return true
            }

            var rawParent: CFTypeRef?
            guard AXUIElementCopyAttributeValue(
                element,
                kAXParentAttribute as CFString,
                &rawParent
            ) == .success,
                  let rawParent else {
                return false
            }
            current = (rawParent as! AXUIElement)
        }
        return false
    }

    private func hidePureVoiceWindows() {
        MainActor.assumeIsolated {
            NSApp.windows.forEach { window in
                guard window.isVisible else { return }
                window.orderOut(nil)
            }
        }
    }

    private func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9

        guard
            let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: true),
            let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: false)
        else {
            return
        }

        keyDown.flags = .maskCommand
        keyUp.flags = .maskCommand
        keyDown.post(tap: .cghidEventTap)
        keyUp.post(tap: .cghidEventTap)
    }

    private func runAppleScriptPaste(bundleIdentifier: String?) -> Bool {
        guard let bundleIdentifier else { return false }
        let source = """
        tell application id "\(bundleIdentifier)" to activate
        delay 0.05
        tell application "System Events" to keystroke "v" using command down
        """
        guard let script = NSAppleScript(source: source) else { return false }
        var error: NSDictionary?
        script.executeAndReturnError(&error)
        return error == nil
    }

    static func replacingSelectedText(
        in currentValue: String,
        with replacement: String,
        selectedRange: CFRange
    ) -> String? {
        let currentNSString = currentValue as NSString
        guard selectedRange.location >= 0,
              selectedRange.length >= 0,
              selectedRange.location <= currentNSString.length,
              selectedRange.location + selectedRange.length <= currentNSString.length else {
            return nil
        }

        return currentNSString.replacingCharacters(
            in: NSRange(location: selectedRange.location, length: selectedRange.length),
            with: replacement
        )
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
