import Foundation
import PureVoiceCore
import SwiftUI

@MainActor
final class AppState: ObservableObject {
    @Published var stage: AppStage = .idle
    @Published var personas: [Persona] = []
    @Published var selectedPersonaID = "default" {
        didSet { saveStringConfig("active_persona_id", selectedPersonaID) }
    }
    @Published var selectedSTTEngine: STTEngine = .whisper {
        didSet { saveStringConfig("stt_engine", selectedSTTEngine.rawValue) }
    }
    @Published var endpointURLString = "http://127.0.0.1:8000" {
        didSet { saveStringConfig("olmx_base_url", endpointURLString) }
    }
    @Published var apiKeyInput = ""
    @Published var apiKeyPresent = false
    @Published var models: [OLMXModel] = []
    @Published var selectedModelID = "" {
        didSet { saveStringConfig("selected_llm_model", selectedModelID) }
    }
    @Published var saveHistory = true {
        didSet { saveBoolConfig("save_history", saveHistory) }
    }
    @Published var llmStatus = "Not checked"
    @Published var whisperHealth = STTHealth(engine: "whisper", available: false, message: "Not checked")
    @Published var parakeetHealth = STTHealth(engine: "parakeet", available: false, message: "Not checked")
    @Published var transcriptPreview = ""
    @Published var polishedPreview = ""
    @Published var errorMessage: String?
    @Published var lastPasteStatus: PasteStatus?

    private let audioRecorder = AudioRecorderService()
    private let keychain = KeychainStore()
    private let pasteService = PasteService()
    private let hotKeyService = HotKeyService()
    private var store: SQLiteStore?
    private var sttClient: STTHelperClient?
    private var activeAudioURL: URL?
    private var originalTarget: FocusTarget?
    private var loaded = false

    var selectedPersona: Persona {
        personas.first { $0.id == selectedPersonaID } ?? personas.first ?? PersonaDefaults.defaultPersonas[0]
    }

    var activeModelLabel: String {
        selectedModelID.isEmpty ? "No model selected" : selectedModelID
    }

    var stageIconName: String {
        switch stage {
        case .idle: "waveform"
        case .recording: "record.circle.fill"
        case .transcribing: "text.bubble"
        case .polishing: "sparkles"
        case .pasted: "checkmark.circle.fill"
        case .copied: "doc.on.clipboard"
        case .error: "exclamationmark.triangle.fill"
        }
    }

    var canUseSelectedSTTEngine: Bool {
        switch selectedSTTEngine {
        case .whisper: whisperHealth.available
        case .parakeet: parakeetHealth.available
        }
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true

        do {
            let store = try SQLiteStore(databaseURL: SQLiteStore.defaultDatabaseURL())
            self.store = store
            personas = try store.loadPersonas()
            selectedPersonaID = readStringConfig("active_persona_id") ?? "default"
            endpointURLString = (readStringConfig("olmx_base_url") ?? "http://127.0.0.1:8000")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            selectedModelID = readStringConfig("selected_llm_model") ?? ""
            if let rawEngine = readStringConfig("stt_engine"), let engine = STTEngine(rawValue: rawEngine) {
                selectedSTTEngine = engine
            }
            saveHistory = readBoolConfig("save_history") ?? true
        } catch {
            errorMessage = error.localizedDescription
            stage = .error
        }

        let bundledHelperURL = Bundle.main.resourceURL?.appendingPathComponent("stt_helper.py")
        let sourceHelperURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("Sources/PureVoiceApp/Resources/stt_helper.py")
        let helperURL = if let bundledHelperURL, FileManager.default.fileExists(atPath: bundledHelperURL.path) {
            bundledHelperURL
        } else {
            sourceHelperURL
        }
        sttClient = STTHelperClient(helperURL: helperURL)
        apiKeyPresent = ((try? keychain.read()) ?? nil)?.isEmpty == false

        hotKeyService.start { [weak self] in
            Task { await self?.toggleRecording() }
        }

        _ = pasteService.hasAccessibilityPermission(prompt: true)
        await refreshHealth()
    }

    func saveAPIKey() async {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Enter your OLMX API key first."
            stage = .error
            return
        }

        let normalizedEndpoint = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedEndpoint.isEmpty else {
            errorMessage = "Enter a valid OLMX endpoint URL first."
            stage = .error
            return
        }

        do {
            if endpointURLString != normalizedEndpoint {
                endpointURLString = normalizedEndpoint
            }

            try keychain.save(trimmed)
            apiKeyInput = ""
            apiKeyPresent = true
            errorMessage = nil
            llmStatus = "API key saved. Refreshing models..."
            stage = .idle

            do {
                let client = try makeOLMXClient()
                let fetched = try await client.models(apiKey: trimmed)
                models = fetched
                try store?.cacheModels(endpointURL: endpointURLString, models: fetched)
                adjustModelSelectionAfterModelRefresh(fetched: fetched)

                llmStatus = fetched.isEmpty
                    ? "API key saved. No models returned for this endpoint."
                    : "API key saved. \(fetched.count) models loaded."
            } catch {
                if let error = error as? OLMXClientError, case .authenticationRequired = error {
                    try? keychain.delete()
                    apiKeyPresent = false
                    errorMessage = "OLMX rejected the API key. Check your key and try again."
                    stage = .error
                } else {
                    errorMessage = nil
                    llmStatus = "Key saved, but model refresh failed: \(error.localizedDescription)"
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            stage = .error
            llmStatus = error.localizedDescription
        }
    }

    func refreshHealth() async {
        await refreshLLMHealth()
        await refreshSTTHealth()
    }

    func refreshLLMHealth() async {
        do {
            let client = try makeOLMXClient()
            let health = try await {
                if let key = try? requireAPIKey() {
                    return try await client.health(apiKey: key)
                }
                return try await client.health()
            }()
            llmStatus = health.status == "healthy" ? "OLMX healthy" : "OLMX: \(health.status)"
            if selectedModelID.isEmpty, let defaultModel = health.defaultModel {
                selectedModelID = defaultModel
            }
        } catch {
            llmStatus = error.localizedDescription
        }
    }

    func refreshModels() async {
        endpointURLString = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            let key = try requireAPIKey()
            let client = try makeOLMXClient()
            let fetched = try await client.models(apiKey: key)
            models = fetched
            try store?.cacheModels(endpointURL: endpointURLString, models: fetched)
            adjustModelSelectionAfterModelRefresh(fetched: fetched)

            llmStatus = selectedModelID.isEmpty
                ? "Models loaded. Select one to enable polishing."
                : "Models loaded."
            errorMessage = nil
            if stage == .error {
                stage = .idle
            }
        } catch {
            errorMessage = error.localizedDescription
            llmStatus = error.localizedDescription
            stage = .error
        }
    }

    func refreshSTTHealth() async {
        guard let sttClient else { return }
        async let whisper = sttClient.health(engine: .whisper)
        async let parakeet = sttClient.health(engine: .parakeet)
        whisperHealth = await whisper
        parakeetHealth = await parakeet

        if selectedSTTEngine == .parakeet, !parakeetHealth.available {
            selectedSTTEngine = .whisper
        }
    }

    func toggleRecording() async {
        switch stage {
        case .recording:
            await stopAndProcessRecording()
        case .transcribing, .polishing:
            return
        default:
            await startRecording()
        }
    }

    func startRecording() async {
        let micAllowed = await audioRecorder.requestPermission()
        guard micAllowed else {
            fail(AudioRecorderError.microphoneDenied)
            return
        }

        guard canUseSelectedSTTEngine else {
            failMessage("\(selectedSTTEngine.displayName) is not available. Check STT setup.")
            return
        }

        do {
            transcriptPreview = ""
            polishedPreview = ""
            errorMessage = nil
            lastPasteStatus = nil
            originalTarget = pasteService.captureFocus()
            activeAudioURL = try audioRecorder.startRecording()
            stage = .recording
        } catch {
            fail(error)
        }
    }

    func stopAndProcessRecording() async {
        guard let audioURL = audioRecorder.stopRecording() ?? activeAudioURL else {
            failMessage("No recording was available to process.")
            return
        }

        guard !selectedModelID.isEmpty else {
            failMessage("Select an OLMX model before recording.")
            return
        }

        let overallStart = Date()
        stage = .transcribing

        do {
            guard let sttClient else {
                throw STTHelperError.helperMissing("stt_helper.py")
            }

            let sttResult = try await sttClient.transcribe(
                audioURL: audioURL,
                engine: selectedSTTEngine,
                model: nil
            )
            transcriptPreview = sttResult.rawText

            stage = .polishing
            let polishStart = Date()
            let key = try requireAPIKey()
            let polished = try await makeOLMXClient().polish(
                transcript: sttResult.rawText,
                persona: selectedPersona,
                model: selectedModelID,
                apiKey: key
            )
            let polishingLatency = Int(Date().timeIntervalSince(polishStart) * 1000)
            polishedPreview = polished

            let pasteStatus = pasteService.pasteOrCopy(polished, originalTarget: originalTarget)
            lastPasteStatus = pasteStatus
            stage = pasteStatus == .pasted ? .pasted : .copied

            if saveHistory {
                let record = TranscriptRecord(
                    rawText: sttResult.rawText,
                    polishedText: polished,
                    personaID: selectedPersona.id,
                    sttEngine: sttResult.engine,
                    sttModel: sttResult.model,
                    llmEndpointURL: endpointURLString,
                    llmModel: selectedModelID,
                    transcriptionLatencyMs: sttResult.latencyMs,
                    polishingLatencyMs: polishingLatency,
                    endToEndLatencyMs: Int(Date().timeIntervalSince(overallStart) * 1000),
                    pasteStatus: pasteStatus
                )
                try store?.insertTranscript(record)
            }

            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            fail(error)
        }
    }

    private func requireAPIKey() throws -> String {
        guard let rawKey = try keychain.read(),
              let key = Optional(rawKey).map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) }),
              !key.isEmpty else {
            throw OLMXClientError.authenticationRequired
        }
        return key
    }

    private func makeOLMXClient() throws -> OLMXClient {
        try OLMXClient(baseURLString: endpointURLString)
    }

    private func fail(_ error: Error) {
        failMessage(error.localizedDescription)
    }

    private func failMessage(_ message: String) {
        errorMessage = message
        stage = .error
    }

    private func readStringConfig(_ key: String) -> String? {
        guard
            let raw = try? store?.loadConfig(key: key),
            let data = raw.data(using: .utf8),
            let value = try? JSONDecoder().decode(String.self, from: data)
        else {
            return nil
        }
        return value
    }

    private func readBoolConfig(_ key: String) -> Bool? {
        guard
            let raw = try? store?.loadConfig(key: key),
            let data = raw.data(using: .utf8),
            let value = try? JSONDecoder().decode(Bool.self, from: data)
        else {
            return nil
        }
        return value
    }

    private func saveStringConfig(_ key: String, _ value: String) {
        guard let data = try? JSONEncoder().encode(value), let raw = String(data: data, encoding: .utf8) else { return }
        try? store?.saveConfig(key: key, valueJSON: raw)
    }

    private func saveBoolConfig(_ key: String, _ value: Bool) {
        guard let data = try? JSONEncoder().encode(value), let raw = String(data: data, encoding: .utf8) else { return }
        try? store?.saveConfig(key: key, valueJSON: raw)
    }

    private func adjustModelSelectionAfterModelRefresh(fetched: [OLMXModel]) {
        if !selectedModelID.isEmpty && !fetched.contains(where: { $0.id == selectedModelID }) {
            selectedModelID = ""
        }

        if selectedModelID.isEmpty {
            selectedModelID = fetched.first?.id ?? ""
        }
    }
}
