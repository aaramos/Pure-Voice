import Foundation

public enum AppStage: String, Codable, CaseIterable, Sendable {
    case idle
    case recording
    case transcribing
    case polishing
    case pasted
    case copied
    case error

    public var label: String {
        switch self {
        case .idle: "Ready"
        case .recording: "Recording"
        case .transcribing: "Transcribing"
        case .polishing: "Refining"
        case .pasted: "Pasted"
        case .copied: "Copied"
        case .error: "Needs attention"
        }
    }
}

public enum STTEngine: String, Codable, CaseIterable, Identifiable, Sendable {
    case whisper
    case parakeet

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .whisper: "Whisper"
        case .parakeet: "Parakeet"
        }
    }
}

public enum HotkeyAction: String, Codable, CaseIterable, Identifiable, Sendable {
    case pushToRecord
    case pushToRecordStop
    case pushToTalk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pushToRecord: "Start Recording"
        case .pushToRecordStop: "Stop Recording"
        case .pushToTalk: "Push to Talk"
        }
    }
}

public enum HotkeyPhase: String, Codable, Sendable {
    case keyDown
    case keyUp
}

public enum RecordingMode: String, Codable, CaseIterable, Identifiable, Sendable {
    case pushToRecord
    case pushToTalk

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .pushToRecord: "Push to Record"
        case .pushToTalk: "Push to Talk"
        }
    }

    public var detail: String {
        switch self {
        case .pushToRecord: "Press the start shortcut to begin. Press the stop shortcut to finish."
        case .pushToTalk: "Hold the Start shortcut for 1.5 seconds to begin. Release to stop."
        }
    }
}

public struct HotkeyBinding: Codable, Equatable, Sendable {
    public var keyCodes: [UInt16]
    public var mouseButtons: [Int64]
    public var modifierFlags: UInt64

    public var keyCode: UInt16 {
        keyCodes.first ?? 0
    }

    public init(keyCode: UInt16, modifierFlags: UInt64) {
        self.init(
            keyCodes: Self.normalizedKeyCodes([keyCode]),
            mouseButtons: [],
            modifierFlags: modifierFlags
        )
    }

    public init(keyCodes: [UInt16] = [], mouseButtons: [Int64] = [], modifierFlags: UInt64) {
        self.keyCodes = Self.normalizedKeyCodes(keyCodes)
        self.mouseButtons = Self.normalizedMouseButtons(mouseButtons)
        self.modifierFlags = modifierFlags
    }

    enum CodingKeys: String, CodingKey {
        case keyCode
        case keyCodes
        case mouseButtons
        case modifierFlags
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let modifierFlags = try container.decode(UInt64.self, forKey: .modifierFlags)
        let decodedKeyCodes = try container.decodeIfPresent([UInt16].self, forKey: .keyCodes)
        let decodedMouseButtons = try container.decodeIfPresent([Int64].self, forKey: .mouseButtons) ?? []

        if let decodedKeyCodes {
            self.init(keyCodes: decodedKeyCodes, mouseButtons: decodedMouseButtons, modifierFlags: modifierFlags)
            return
        }

        if let legacyKeyCode = try container.decodeIfPresent(UInt16.self, forKey: .keyCode),
           !Self.isModifierKey(legacyKeyCode) {
            self.init(keyCodes: [legacyKeyCode], mouseButtons: decodedMouseButtons, modifierFlags: modifierFlags)
        } else {
            self.init(keyCodes: [], mouseButtons: decodedMouseButtons, modifierFlags: modifierFlags)
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(keyCodes, forKey: .keyCodes)
        try container.encode(mouseButtons, forKey: .mouseButtons)
        try container.encode(modifierFlags, forKey: .modifierFlags)
    }

    private static func normalizedKeyCodes(_ keyCodes: [UInt16]) -> [UInt16] {
        Array(Set(keyCodes.filter { !isModifierKey($0) })).sorted()
    }

    private static func normalizedMouseButtons(_ mouseButtons: [Int64]) -> [Int64] {
        Array(Set(mouseButtons)).sorted()
    }

    private static func isModifierKey(_ keyCode: UInt16) -> Bool {
        switch keyCode {
        case 54, 55, 56, 57, 58, 59, 60, 61, 62, 63:
            return true
        default:
            return false
        }
    }
}

public enum PasteStatus: String, Codable, Sendable {
    case pasted
    case copied
    case failed
}

public enum PasteFallbackReason: String, Codable, Sendable {
    case none
    case clipboardUnavailable
    case accessibilityPermissionMissing
    case targetUnavailable
    case targetActivationFailed
    case focusedInputUnavailable
    case pasteEventFailed
}

public struct PasteDeliveryResult: Sendable {
    public var status: PasteStatus
    public var fallbackReason: PasteFallbackReason
    public var target: FocusTarget?

    public init(
        status: PasteStatus,
        fallbackReason: PasteFallbackReason = .none,
        target: FocusTarget? = nil
    ) {
        self.status = status
        self.fallbackReason = fallbackReason
        self.target = target
    }
}

public struct Persona: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var name: String
    public var systemPrompt: String
    public var isBuiltin: Bool
    public var isDefault: Bool
    public var createdAt: Date
    public var updatedAt: Date

    public init(
        id: String,
        name: String,
        systemPrompt: String,
        isBuiltin: Bool,
        isDefault: Bool,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.name = name
        self.systemPrompt = systemPrompt
        self.isBuiltin = isBuiltin
        self.isDefault = isDefault
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

public struct TranscriptRecord: Identifiable, Codable, Sendable {
    public var id: String
    public var rawText: String
    public var polishedText: String
    public var personaID: String
    public var sttEngine: String
    public var sttModel: String
    public var llmEndpointURL: String
    public var llmModel: String
    public var transcriptionLatencyMs: Int
    public var polishingLatencyMs: Int
    public var endToEndLatencyMs: Int
    public var pasteStatus: PasteStatus
    public var errorMessage: String?
    public var rating: Int?
    public var createdAt: Date

    public init(
        id: String = UUID().uuidString,
        rawText: String,
        polishedText: String,
        personaID: String,
        sttEngine: String,
        sttModel: String,
        llmEndpointURL: String,
        llmModel: String,
        transcriptionLatencyMs: Int,
        polishingLatencyMs: Int,
        endToEndLatencyMs: Int,
        pasteStatus: PasteStatus,
        errorMessage: String? = nil,
        rating: Int? = nil,
        createdAt: Date = Date()
    ) {
        self.id = id
        self.rawText = rawText
        self.polishedText = polishedText
        self.personaID = personaID
        self.sttEngine = sttEngine
        self.sttModel = sttModel
        self.llmEndpointURL = llmEndpointURL
        self.llmModel = llmModel
        self.transcriptionLatencyMs = transcriptionLatencyMs
        self.polishingLatencyMs = polishingLatencyMs
        self.endToEndLatencyMs = endToEndLatencyMs
        self.pasteStatus = pasteStatus
        self.errorMessage = errorMessage
        self.rating = rating
        self.createdAt = createdAt
    }
}

public struct STTResult: Codable, Equatable, Sendable {
    public var engine: String
    public var model: String
    public var rawText: String
    public var latencyMs: Int
    public var status: String
    public var errorMessage: String?

    public init(
        engine: String,
        model: String,
        rawText: String,
        latencyMs: Int,
        status: String,
        errorMessage: String? = nil
    ) {
        self.engine = engine
        self.model = model
        self.rawText = rawText
        self.latencyMs = latencyMs
        self.status = status
        self.errorMessage = errorMessage
    }

    enum CodingKeys: String, CodingKey {
        case engine
        case model
        case rawText = "raw_text"
        case latencyMs = "latency_ms"
        case status
        case errorMessage = "error_message"
    }
}

public struct STTHealth: Codable, Equatable, Sendable {
    public var engine: String
    public var available: Bool
    public var message: String
    public var model: String?

    public init(engine: String, available: Bool, message: String, model: String? = nil) {
        self.engine = engine
        self.available = available
        self.message = message
        self.model = model
    }
}

public struct FocusTarget: Codable, Equatable, Sendable {
    public var processIdentifier: Int32
    public var applicationName: String?
    public var bundleIdentifier: String?

    public init(processIdentifier: Int32, applicationName: String?, bundleIdentifier: String? = nil) {
        self.processIdentifier = processIdentifier
        self.applicationName = applicationName
        self.bundleIdentifier = bundleIdentifier
    }
}
