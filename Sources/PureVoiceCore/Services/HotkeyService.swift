import ApplicationServices
import Foundation

public enum HotkeyCaptureResult: Sendable {
    case captured(HotkeyBinding)
    case cancelled
}

public enum HotkeyConflictDetector {
    public static func warning(for binding: HotkeyBinding) -> String? {
        let flags = CGEventFlags(rawValue: binding.modifierFlags)
        let hasCommand = flags.contains(.maskCommand)
        let hasControl = flags.contains(.maskControl)
        let hasOption = flags.contains(.maskAlternate)
        let hasShift = flags.contains(.maskShift)
        let hasAnyModifier = hasCommand || hasControl || hasOption || hasShift || flags.contains(.maskSecondaryFn)

        if !hasAnyModifier {
            return "This shortcut has no modifier key and may conflict with normal typing."
        }

        if binding.keyCode == HotkeyKeyCode.space, hasCommand, !hasOption, !hasShift {
            return "Command-Space is commonly reserved for Spotlight or input switching."
        }

        if binding.keyCode == HotkeyKeyCode.space, hasControl, !hasCommand, !hasOption, !hasShift {
            return "Control-Space is commonly used by macOS or text input tools."
        }

        if binding.keyCode == HotkeyKeyCode.escape {
            return "Escape is reserved for cancelling shortcut capture."
        }

        return nil
    }
}

public enum HotkeyKeyCode {
    public static let space: UInt16 = 49
    public static let escape: UInt16 = 53
    public static let leftCommand: UInt16 = 55
    public static let rightCommand: UInt16 = 54
    public static let leftOption: UInt16 = 58
    public static let rightOption: UInt16 = 61
}

public extension HotkeyBinding {
    static let defaultPushToRecord = HotkeyBinding(
        keyCode: HotkeyKeyCode.rightOption,
        modifierFlags: CGEventFlags.pureVoiceRightCommandOption.rawValue
    )

    static let defaultPushToTalk = HotkeyBinding(
        keyCode: HotkeyKeyCode.leftOption,
        modifierFlags: CGEventFlags.pureVoiceLeftCommandOption.rawValue
    )

    static let defaultBindings: [HotkeyAction: HotkeyBinding] = [
        .pushToRecord: .defaultPushToRecord,
        .pushToTalk: .defaultPushToTalk
    ]

    var displayString: String {
        HotkeyFormatter.string(for: self)
    }
}

public final class HotkeyService: @unchecked Sendable {
    public typealias EventHandler = @Sendable (HotkeyAction, HotkeyPhase) -> Void
    public typealias CaptureHandler = @Sendable (HotkeyCaptureResult) -> Void

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var bindings: [HotkeyAction: HotkeyBinding] = HotkeyBinding.defaultBindings
    private var activeActions = Set<HotkeyAction>()
    private var handler: EventHandler?
    private var captureHandler: CaptureHandler?
    private var pendingCapture: DispatchWorkItem?

    public init() {}

    deinit {
        stop()
    }

    public var isCapturing: Bool {
        captureHandler != nil
    }

    public func start(
        bindings: [HotkeyAction: HotkeyBinding],
        handler: @escaping EventHandler
    ) {
        self.bindings = Self.mergingDefaults(with: bindings)
        self.handler = handler

        if eventTap != nil {
            return
        }

        let mask = CGEventMask(
            (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
                | (1 << CGEventType.flagsChanged.rawValue)
        )

        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else {
                return Unmanaged.passUnretained(event)
            }

            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handle(type: type, event: event)
        }

        let refcon = UnsafeMutableRawPointer(Unmanaged.passUnretained(self).toOpaque())
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: refcon
        ) else {
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func updateBindings(_ bindings: [HotkeyAction: HotkeyBinding]) {
        self.bindings = Self.mergingDefaults(with: bindings)
    }

    public func beginCapture(handler: @escaping CaptureHandler) {
        pendingCapture?.cancel()
        pendingCapture = nil
        captureHandler = handler
    }

    public func cancelCapture() {
        finishCapture(.cancelled)
    }

    public func stop() {
        pendingCapture?.cancel()
        pendingCapture = nil
        captureHandler = nil
        activeActions.removeAll()

        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
            self.runLoopSource = nil
        }

        if let eventTap {
            CFMachPortInvalidate(eventTap)
            self.eventTap = nil
        }
    }

    private static func mergingDefaults(with bindings: [HotkeyAction: HotkeyBinding]) -> [HotkeyAction: HotkeyBinding] {
        var merged = HotkeyBinding.defaultBindings
        for (action, binding) in bindings {
            merged[action] = binding
        }
        return merged
    }

    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown || type == .keyUp || type == .flagsChanged else {
            return Unmanaged.passUnretained(event)
        }

        if captureHandler != nil {
            handleCapture(type: type, event: event)
            return Unmanaged.passUnretained(event)
        }

        handleHotkey(type: type, event: event)
        return Unmanaged.passUnretained(event)
    }

    private func handleCapture(type: CGEventType, event: CGEvent) {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyDown, keyCode == HotkeyKeyCode.escape {
            finishCapture(.cancelled)
            return
        }

        if type == .keyDown {
            pendingCapture?.cancel()
            let binding = HotkeyBinding(
                keyCode: keyCode,
                modifierFlags: Self.normalizedModifiers(from: event).rawValue
            )
            finishCapture(.captured(binding))
            return
        }

        guard type == .flagsChanged else { return }
        let modifiers = Self.normalizedModifiers(from: event)
        guard !modifiers.isEmpty else { return }

        pendingCapture?.cancel()
        let binding = HotkeyBinding(keyCode: keyCode, modifierFlags: modifiers.rawValue)
        let workItem = DispatchWorkItem { [weak self] in
            self?.finishCapture(.captured(binding))
        }
        pendingCapture = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: workItem)
    }

    private func finishCapture(_ result: HotkeyCaptureResult) {
        pendingCapture?.cancel()
        pendingCapture = nil
        guard let captureHandler else { return }
        self.captureHandler = nil
        captureHandler(result)
    }

    private func handleHotkey(type: CGEventType, event: CGEvent) {
        let isRepeat = event.getIntegerValueField(.keyboardEventAutorepeat) != 0
        if type == .keyDown, isRepeat {
            return
        }

        let matchedActions = Set(bindings.compactMap { action, binding in
            matches(binding, type: type, event: event) ? action : nil
        })

        if type == .keyDown || type == .flagsChanged {
            for action in matchedActions where !activeActions.contains(action) {
                activeActions.insert(action)
                handler?(action, .keyDown)
            }

            for action in activeActions.subtracting(matchedActions) where shouldRelease(action, type: type, event: event) {
                activeActions.remove(action)
                handler?(action, .keyUp)
            }
            return
        }

        if type == .keyUp {
            for action in activeActions where shouldRelease(action, type: type, event: event) {
                activeActions.remove(action)
                handler?(action, .keyUp)
            }
        }
    }

    private func matches(_ binding: HotkeyBinding, type: CGEventType, event: CGEvent) -> Bool {
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))
        let modifiers = Self.normalizedModifiers(from: event)

        if type == .keyDown {
            return keyCode == binding.keyCode && modifiers.rawValue == binding.modifierFlags
        }

        if type == .flagsChanged {
            return keyCode == binding.keyCode && modifiers.rawValue == binding.modifierFlags
        }

        return false
    }

    private func shouldRelease(_ action: HotkeyAction, type: CGEventType, event: CGEvent) -> Bool {
        guard let binding = bindings[action] else { return true }
        let keyCode = UInt16(event.getIntegerValueField(.keyboardEventKeycode))

        if type == .keyUp {
            return keyCode == binding.keyCode
        }

        if type == .flagsChanged {
            return !matches(binding, type: type, event: event)
        }

        return false
    }

    private static func normalizedModifiers(from event: CGEvent) -> CGEventFlags {
        event.flags.intersection(.pureVoiceModifierMask)
    }
}

private enum HotkeyFormatter {
    static func string(for binding: HotkeyBinding) -> String {
        let flags = CGEventFlags(rawValue: binding.modifierFlags)
        var parts: [String] = []

        appendSideAwareModifier(
            to: &parts,
            flags: flags,
            generic: .maskCommand,
            left: .pureVoiceLeftCommand,
            right: .pureVoiceRightCommand,
            genericSymbol: "⌘",
            leftSymbol: "left ⌘",
            rightSymbol: "right ⌘"
        )
        appendSideAwareModifier(
            to: &parts,
            flags: flags,
            generic: .maskAlternate,
            left: .pureVoiceLeftAlternate,
            right: .pureVoiceRightAlternate,
            genericSymbol: "⌥",
            leftSymbol: "left ⌥",
            rightSymbol: "right ⌥"
        )
        appendSideAwareModifier(
            to: &parts,
            flags: flags,
            generic: .maskControl,
            left: .pureVoiceLeftControl,
            right: .pureVoiceRightControl,
            genericSymbol: "⌃",
            leftSymbol: "left ⌃",
            rightSymbol: "right ⌃"
        )
        appendSideAwareModifier(
            to: &parts,
            flags: flags,
            generic: .maskShift,
            left: .pureVoiceLeftShift,
            right: .pureVoiceRightShift,
            genericSymbol: "⇧",
            leftSymbol: "left ⇧",
            rightSymbol: "right ⇧"
        )

        if flags.contains(.maskSecondaryFn) {
            parts.append("fn")
        }

        if let key = keyName(for: binding.keyCode), !isModifierKey(binding.keyCode) {
            parts.append(key)
        }

        return parts.isEmpty ? "Unassigned" : parts.joined(separator: " + ")
    }

    private static func appendSideAwareModifier(
        to parts: inout [String],
        flags: CGEventFlags,
        generic: CGEventFlags,
        left: CGEventFlags,
        right: CGEventFlags,
        genericSymbol: String,
        leftSymbol: String,
        rightSymbol: String
    ) {
        let hasLeft = flags.contains(left)
        let hasRight = flags.contains(right)
        if hasLeft {
            parts.append(leftSymbol)
        }
        if hasRight {
            parts.append(rightSymbol)
        }
        if !hasLeft, !hasRight, flags.contains(generic) {
            parts.append(genericSymbol)
        }
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }

    private static func keyName(for keyCode: UInt16) -> String? {
        switch keyCode {
        case HotkeyKeyCode.space: return "Space"
        case HotkeyKeyCode.escape: return "Escape"
        case 0: return "A"
        case 1: return "S"
        case 2: return "D"
        case 3: return "F"
        case 4: return "H"
        case 5: return "G"
        case 6: return "Z"
        case 7: return "X"
        case 8: return "C"
        case 9: return "V"
        case 11: return "B"
        case 12: return "Q"
        case 13: return "W"
        case 14: return "E"
        case 15: return "R"
        case 16: return "Y"
        case 17: return "T"
        case 31: return "O"
        case 32: return "U"
        case 34: return "I"
        case 35: return "P"
        case 37: return "L"
        case 38: return "J"
        case 40: return "K"
        case 45: return "N"
        case 46: return "M"
        default:
            return "Key \(keyCode)"
        }
    }
}

private extension CGEventFlags {
    static let pureVoiceLeftControl = CGEventFlags(rawValue: 0x0000_0001)
    static let pureVoiceLeftShift = CGEventFlags(rawValue: 0x0000_0002)
    static let pureVoiceRightShift = CGEventFlags(rawValue: 0x0000_0004)
    static let pureVoiceLeftCommand = CGEventFlags(rawValue: 0x0000_0008)
    static let pureVoiceRightCommand = CGEventFlags(rawValue: 0x0000_0010)
    static let pureVoiceLeftAlternate = CGEventFlags(rawValue: 0x0000_0020)
    static let pureVoiceRightAlternate = CGEventFlags(rawValue: 0x0000_0040)
    static let pureVoiceRightControl = CGEventFlags(rawValue: 0x0000_2000)

    static let pureVoiceModifierMask: CGEventFlags = [
        .maskShift,
        .maskControl,
        .maskAlternate,
        .maskCommand,
        .maskSecondaryFn,
        .pureVoiceLeftShift,
        .pureVoiceRightShift,
        .pureVoiceLeftControl,
        .pureVoiceRightControl,
        .pureVoiceLeftAlternate,
        .pureVoiceRightAlternate,
        .pureVoiceLeftCommand,
        .pureVoiceRightCommand
    ]

    static let pureVoiceRightCommandOption = CGEventFlags([
        .maskCommand,
        .pureVoiceRightCommand,
        .maskAlternate,
        .pureVoiceRightAlternate
    ])

    static let pureVoiceLeftCommandOption = CGEventFlags([
        .maskCommand,
        .pureVoiceLeftCommand,
        .maskAlternate,
        .pureVoiceLeftAlternate
    ])
}
