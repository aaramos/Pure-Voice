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

public enum PasteStatus: String, Codable, Sendable {
    case pasted
    case copied
    case failed
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

public struct OLMXModel: Identifiable, Codable, Hashable, Sendable {
    public var id: String
    public var object: String?
    public var ownedBy: String?

    public init(id: String, object: String? = nil, ownedBy: String? = nil) {
        self.id = id
        self.object = object
        self.ownedBy = ownedBy
    }

    enum CodingKeys: String, CodingKey {
        case id
        case object
        case ownedBy = "owned_by"
    }
}

public struct OLMXHealth: Codable, Equatable, Sendable {
    public var status: String
    public var defaultModel: String?

    public init(status: String, defaultModel: String?) {
        self.status = status
        self.defaultModel = defaultModel
    }

    enum CodingKeys: String, CodingKey {
        case status
        case defaultModel = "default_model"
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

    public init(processIdentifier: Int32, applicationName: String?) {
        self.processIdentifier = processIdentifier
        self.applicationName = applicationName
    }
}
