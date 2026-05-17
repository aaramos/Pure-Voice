import AppKit
import Foundation
import OSLog
import PureVoiceCore
import SwiftUI

private let pipelineLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.adrian.purevoice",
    category: "Pipeline"
)

enum RecordingStatus: Equatable {
    case idle
    case recording
    case processing
    case pastedToField
    case copiedToClipboard
    case copiedRawTranscript
    case retrying(attempt: Int)
    case modelUnavailable
}

private enum OutputDeliveryError: LocalizedError {
    case clipboardUnavailable

    var errorDescription: String? {
        switch self {
        case .clipboardUnavailable:
            return "Pure Voice could not write the output to the clipboard."
        }
    }
}

private struct PolishingResult {
    var text: String
    var endpointLabel: String
    var modelLabel: String
}

struct AttentionGuidance: Equatable {
    enum Action: Equatable {
        case openAppSettings
        case openMicrophonePrivacy
        case openAccessibilityPrivacy
        case refreshHealth
        case startRecording
    }

    var title: String
    var message: String
    var nextStep: String
    var actionTitle: String
    var action: Action
}

@MainActor
final class AppState: ObservableObject {
    @Published var stage: AppStage = .idle
    @Published var personas: [Persona] = []
    @Published var selectedPersonaID = "clarity" {
        didSet { saveStringConfig("active_persona_id", selectedPersonaID) }
    }
    @Published var selectedSTTEngine: STTEngine = .whisper {
        didSet { saveStringConfig("stt_engine", selectedSTTEngine.rawValue) }
    }
    @Published var saveHistory = true {
        didSet { saveBoolConfig("save_history", saveHistory) }
    }
    @Published var llmStatus = "Not checked"
    @Published var appleFoundationAvailability = AppleFoundationModelClient.availability
    @Published var whisperHealth = STTHealth(engine: "whisper", available: false, message: "Not checked")
    @Published var transcriptPreview = ""
    @Published var polishedPreview = ""
    @Published var errorMessage: String?
    @Published var lastPasteStatus: PasteStatus?
    @Published var lastPasteFallbackReason: PasteFallbackReason?
    @Published var recordingStatus: RecordingStatus = .idle {
        didSet { handleRecordingStatusTransition(from: oldValue, to: recordingStatus) }
    }
    @Published var waveformLevels: [CGFloat] = Array(repeating: 4, count: 38)

    private let audioRecorder = AudioRecorderService()
    private let appleClient = AppleFoundationModelClient()
    private let pasteService = PasteService()
    private let hotKeyService = HotKeyService()
    private var store: SQLiteStore?
    private var sttClient: STTHelperClient?
    private var activeAudioURL: URL?
    private var originalTarget: FocusTarget?
    private var loaded = false
    private var meteringTimer: Timer?
    private var recordingStatusPanel: RecordingStatusPanel?
    private var recordingStatusDismissTask: Task<Void, Never>?

    init() {
        appleFoundationAvailability = AppleFoundationModelClient.availability
    }

    var selectedPersona: Persona {
        personas.first { $0.id == selectedPersonaID } ?? personas.first ?? PersonaDefaults.defaultPersonas[0]
    }

    var activeModelLabel: String {
        "Apple On-Device"
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
        whisperHealth.available
    }

    var appleFoundationStatusText: String {
        if appleFoundationAvailability == .available {
            return "\(appleFoundationAvailability.statusText) ✓"
        }
        return appleFoundationAvailability.statusText
    }

    var needsAttention: Bool {
        stage == .error || errorMessage?.isEmpty == false
    }

    var latestOutputText: String {
        if !polishedPreview.isEmpty {
            return polishedPreview
        }
        return transcriptPreview
    }

    var hasLatestOutput: Bool {
        !latestOutputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var latestOutputTitle: String {
        switch lastPasteStatus {
        case .pasted:
            return "Pasted Into Target App"
        case .copied:
            return "Copied To Clipboard"
        case .failed:
            return "Output Delivery Failed"
        case nil:
            return "Latest Output"
        }
    }

    var latestOutputInstruction: String {
        switch lastPasteStatus {
        case .pasted:
            return "Pure Voice pasted this into the app that was active when recording started."
        case .copied:
            switch lastPasteFallbackReason {
            case .accessibilityPermissionMissing:
                return "Pure Voice copied this because macOS has not granted Accessibility control to Pure Voice. Enable it in System Settings if you want automatic paste."
            case .targetUnavailable:
                return "Pure Voice copied this because it could not identify the target field. Click the field first, then start recording with the hotkey."
            case .targetActivationFailed:
                return "Pure Voice copied this because it could not bring the original target app back to the front."
            case .pasteEventFailed:
                return "Pure Voice copied this because macOS did not accept the paste keystroke."
            case .clipboardUnavailable:
                return "Pure Voice could not complete automatic paste and had trouble writing the clipboard."
            case .none?, nil:
                return "Pure Voice copied this because it could not confirm paste access to the target app. Press Command+V there, or enable Pure Voice in Accessibility if you want automatic paste."
            }
        case .failed:
            return "Pure Voice kept the text here. Use Copy Again, then paste it manually."
        case nil:
            return "This is the most recent transcript output."
        }
    }

    var attentionGuidance: AttentionGuidance {
        let message = errorMessage?.trimmingCharacters(in: .whitespacesAndNewlines)
        let issue = message?.isEmpty == false ? message! : "Pure Voice needs setup before it can continue."
        let lowered = issue.lowercased()

        if lowered.contains("microphone") {
            return AttentionGuidance(
                title: "Microphone Access Blocked",
                message: issue,
                nextStep: "Enable Pure Voice in System Settings > Privacy & Security > Microphone, then try recording again.",
                actionTitle: "Open Microphone Privacy",
                action: .openMicrophonePrivacy
            )
        }

        if lowered.contains("accessibility")
            || lowered.contains("control")
            || lowered.contains("paste")
            || lowered.contains("clipboard")
        {
            return AttentionGuidance(
                title: "Paste Permission Needs Attention",
                message: issue,
                nextStep: "Enable Pure Voice in System Settings > Privacy & Security > Accessibility so it can paste into the app where you started recording. If you only want clipboard fallback, the transcript is copied when paste is unavailable.",
                actionTitle: "Open Accessibility Privacy",
                action: .openAccessibilityPrivacy
            )
        }

        if lowered.contains("apple intelligence")
            || lowered.contains("foundation")
            || lowered.contains("model")
        {
            return AttentionGuidance(
                title: "Apple Intelligence Needs Attention",
                message: issue,
                nextStep: "Enable Apple Intelligence in System Settings, wait for the on-device model to finish downloading, then try again.",
                actionTitle: "Open Pure Voice Settings",
                action: .openAppSettings
            )
        }

        if lowered.contains("stt")
            || lowered.contains("transcription")
            || lowered.contains("transcribe")
            || lowered.contains("helper")
            || lowered.contains("whisper")
        {
            return AttentionGuidance(
                title: "Speech Transcription Needs Setup",
                message: issue,
                nextStep: "Open Pure Voice settings and check Whisper health.",
                actionTitle: "Open Pure Voice Settings",
                action: .openAppSettings
            )
        }

        if lowered.contains("no recording") || lowered.contains("audio recorder") {
            return AttentionGuidance(
                title: "Recording Did Not Start",
                message: issue,
                nextStep: "Start a new recording and keep holding until you are ready to stop.",
                actionTitle: "Try Recording Again",
                action: .startRecording
            )
        }

        return AttentionGuidance(
            title: "Pure Voice Needs Attention",
            message: issue,
            nextStep: "Refresh health. If the issue remains, open Pure Voice settings and check microphone, Whisper, and Apple Intelligence status.",
            actionTitle: "Refresh Health",
            action: .refreshHealth
        )
    }

    func loadIfNeeded() async {
        guard !loaded else { return }
        loaded = true

        do {
            let store = try SQLiteStore(databaseURL: SQLiteStore.defaultDatabaseURL())
            self.store = store
            personas = try store.loadPersonas()
            let defaultPersonaID = personas.first(where: \.isDefault)?.id ?? "clarity"
            let storedPersonaID = readStringConfig("active_persona_id") ?? defaultPersonaID
            selectedPersonaID = personas.contains { $0.id == storedPersonaID }
                ? storedPersonaID
                : defaultPersonaID
            if let rawEngine = readStringConfig("stt_engine"),
               let engine = STTEngine(rawValue: rawEngine),
               engine == .whisper {
                selectedSTTEngine = engine
            } else {
                selectedSTTEngine = .whisper
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

        hotKeyService.start(
            onStart: { [weak self] in
                Task { await self?.startRecordingFromHotKey() }
            },
            onStop: { [weak self] in
                Task { await self?.stopRecordingFromHotKey() }
            }
        )

        _ = pasteService.hasAccessibilityPermission(prompt: false)
        await refreshHealth()
    }

    func refreshHealth() async {
        await refreshAppleFoundationAvailability()
        await refreshSTTHealth()
    }

    @discardableResult
    func refreshAppleFoundationAvailability() async -> AppleFoundationModelAvailability {
        let availability = AppleFoundationModelClient.availability
        appleFoundationAvailability = availability

        switch availability {
        case .available:
            llmStatus = "Apple Intelligence available."
        case .appleIntelligenceNotEnabled:
            llmStatus = "Enable Apple Intelligence in System Settings to use on-device polishing."
        case .deviceNotEligible:
            llmStatus = "This device cannot run Apple Foundation Models."
        case .modelNotReady:
            llmStatus = "Apple Intelligence model loading..."
        case .unavailable(let reason):
            llmStatus = "Apple Foundation Models unavailable: \(reason)."
        }

        return availability
    }

    func performAttentionAction() {
        switch attentionGuidance.action {
        case .openAppSettings:
            openSettings()
        case .openMicrophonePrivacy:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
        case .openAccessibilityPrivacy:
            openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
        case .refreshHealth:
            Task { await refreshHealth() }
        case .startRecording:
            Task { await startRecording() }
        }
    }

    func copyAttentionDetailsToClipboard() {
        let guidance = attentionGuidance
        let details = """
        Pure Voice status: \(stage.label)
        Issue: \(guidance.message)
        Next step: \(guidance.nextStep)
        Persona: \(selectedPersona.name)
        Polishing: \(activeModelLabel)
        Apple Intelligence: \(llmStatus)
        Whisper: \(whisperHealth.message)
        """
        _ = pasteService.copyToPasteboard(details)
    }

    func copyLatestOutputToClipboard() {
        _ = pasteService.copyToPasteboard(latestOutputText)
        lastPasteStatus = .copied
        lastPasteFallbackReason = PasteFallbackReason.none
        stage = .copied
    }

    func refreshSTTHealth() async {
        guard let sttClient else { return }
        whisperHealth = await sttClient.health(engine: .whisper)
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

    func startRecordingFromHotKey() async {
        switch stage {
        case .recording, .transcribing, .polishing:
            return
        default:
            await startRecording()
        }
    }

    func stopRecordingFromHotKey() async {
        guard stage == .recording else { return }
        await stopAndProcessRecording()
    }

    func startRecording() async {
        let targetAtGesture = pasteService.captureFocus()
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
            lastPasteFallbackReason = nil
            originalTarget = targetAtGesture
            activeAudioURL = try audioRecorder.startRecording()
            waveformLevels = Array(repeating: 4, count: 38)
            startMeteringTimer()
            stage = .recording
            recordingStatus = .recording
        } catch {
            fail(error)
        }
    }

    func stopAndProcessRecording() async {
        stopMeteringTimer()
        guard let audioURL = audioRecorder.stopRecording() ?? activeAudioURL else {
            failMessage("No recording was available to process.")
            return
        }

        let overallStart = Date()
        stage = .transcribing
        recordingStatus = .processing
        var fallbackSTTResult: STTResult?

        do {
            guard let sttClient else {
                throw STTHelperError.helperMissing("stt_helper.py")
            }

            pipelineLogger.info("Pipeline transcribe started using \(self.selectedSTTEngine.rawValue, privacy: .public)")
            let sttResult = try await sttClient.transcribe(
                audioURL: audioURL,
                engine: selectedSTTEngine,
                model: nil
            )
            fallbackSTTResult = sttResult
            transcriptPreview = sttResult.rawText
            let rawCopied = pasteService.copyToPasteboard(sttResult.rawText)
            pipelineLogger.info("Pipeline transcription complete, chars=\(sttResult.rawText.count, privacy: .public), rawClipboardFallback=\(rawCopied, privacy: .public)")

            stage = .polishing
            let polishStart = Date()
            pipelineLogger.info("Pipeline polishing started with backend=Apple Foundation Models, model=\(self.activeModelLabel, privacy: .public)")
            let polishResult = try await polishTranscript(
                transcript: sttResult.rawText,
                persona: selectedPersona
            )
            let polished = polishResult.text
            let polishingLatency = Int(Date().timeIntervalSince(polishStart) * 1000)
            polishedPreview = polished
            pipelineLogger.info("Pipeline polishing complete, chars=\(polished.count, privacy: .public), latencyMs=\(polishingLatency, privacy: .public)")

            let pasteResult = pasteService.pasteOrCopy(polished, originalTarget: originalTarget)
            let pasteStatus = pasteResult.status
            guard pasteStatus != .failed else {
                _ = pasteService.copyToPasteboard(sttResult.rawText)
                throw OutputDeliveryError.clipboardUnavailable
            }

            lastPasteStatus = pasteStatus
            lastPasteFallbackReason = pasteResult.fallbackReason
            stage = pasteStatus == .pasted ? .pasted : .copied
            recordingStatus = pasteStatus == .pasted ? .pastedToField : .copiedToClipboard
            pipelineLogger.info(
                "Pipeline delivered output with status=\(pasteStatus.rawValue, privacy: .public), fallbackReason=\(pasteResult.fallbackReason.rawValue, privacy: .public), target=\(pasteResult.target?.applicationName ?? "none", privacy: .public)"
            )

            if saveHistory {
                let record = TranscriptRecord(
                    rawText: sttResult.rawText,
                    polishedText: polished,
                    personaID: selectedPersona.id,
                    sttEngine: sttResult.engine,
                    sttModel: sttResult.model,
                    llmEndpointURL: polishResult.endpointLabel,
                    llmModel: polishResult.modelLabel,
                    transcriptionLatencyMs: sttResult.latencyMs,
                    polishingLatencyMs: polishingLatency,
                    endToEndLatencyMs: Int(Date().timeIntervalSince(overallStart) * 1000),
                    pasteStatus: pasteStatus
                )
                saveTranscriptRecord(record)
            }

            try? FileManager.default.removeItem(at: audioURL)
        } catch {
            pipelineLogger.error("Pipeline failed: \(error.localizedDescription, privacy: .public)")
            if let fallbackSTTResult {
                deliverRawTranscriptFallback(
                    fallbackSTTResult,
                    audioURL: audioURL,
                    overallStart: overallStart,
                    error: error
                )
            } else {
                fail(error)
            }
        }
    }

    private func deliverRawTranscriptFallback(
        _ sttResult: STTResult,
        audioURL: URL,
        overallStart: Date,
        error: Error
    ) {
        let copied = pasteService.copyToPasteboard(sttResult.rawText)
        transcriptPreview = sttResult.rawText
        polishedPreview = sttResult.rawText
        lastPasteStatus = copied ? .copied : .failed
        lastPasteFallbackReason = copied ? PasteFallbackReason.none : .clipboardUnavailable

        if copied {
            errorMessage = "Polishing failed, so the raw transcript was copied instead: \(error.localizedDescription)"
            stage = .copied
            recordingStatus = .copiedRawTranscript
            pipelineLogger.info("Pipeline copied raw transcript fallback, chars=\(sttResult.rawText.count, privacy: .public)")

            if saveHistory {
                let record = TranscriptRecord(
                    rawText: sttResult.rawText,
                    polishedText: sttResult.rawText,
                    personaID: selectedPersona.id,
                    sttEngine: sttResult.engine,
                    sttModel: sttResult.model,
                    llmEndpointURL: "apple-foundation-models",
                    llmModel: "Apple Foundation Models",
                    transcriptionLatencyMs: sttResult.latencyMs,
                    polishingLatencyMs: 0,
                    endToEndLatencyMs: Int(Date().timeIntervalSince(overallStart) * 1000),
                    pasteStatus: .copied,
                    errorMessage: error.localizedDescription
                )
                saveTranscriptRecord(record)
            }

            try? FileManager.default.removeItem(at: audioURL)
        } else {
            failMessage("Polishing failed, and Pure Voice could not write the raw transcript to the clipboard: \(error.localizedDescription)")
        }
    }

    private func saveTranscriptRecord(_ record: TranscriptRecord) {
        do {
            try store?.insertTranscript(record)
        } catch {
            pipelineLogger.error("Transcript history save failed: \(error.localizedDescription, privacy: .public)")
            errorMessage = "Output copied, but history could not be saved: \(error.localizedDescription)"
        }
    }

    private func polishTranscript(transcript: String, persona: Persona) async throws -> PolishingResult {
        try await polishWithAppleFoundationModels(transcript: transcript, persona: persona)
    }

    private func polishWithAppleFoundationModels(
        transcript: String,
        persona: Persona
    ) async throws -> PolishingResult {
        let availability = await refreshAppleFoundationAvailability()

        switch availability {
        case .available:
            let polished = try await appleClient.polish(
                text: transcript,
                systemPrompt: persona.systemPrompt
            )
            return PolishingResult(
                text: polished,
                endpointLabel: "apple-foundation-models",
                modelLabel: "Apple Foundation Models"
            )

        case .modelNotReady:
            llmStatus = "Apple Intelligence model loading..."
            recordingStatus = .retrying(attempt: 1)
            try await Task.sleep(for: .seconds(10))

            if await refreshAppleFoundationAvailability() == .available {
                let polished = try await appleClient.polish(
                    text: transcript,
                    systemPrompt: persona.systemPrompt
                )
                return PolishingResult(
                    text: polished,
                    endpointLabel: "apple-foundation-models",
                    modelLabel: "Apple Foundation Models"
                )
            }

            throw AppleFoundationModelClient.PolishingError.modelUnavailable

        case .appleIntelligenceNotEnabled, .deviceNotEligible, .unavailable:
            recordingStatus = .modelUnavailable
            throw AppleFoundationModelClient.PolishingError.generationFailed(availability.statusText)
        }
    }

    private func fail(_ error: Error) {
        failMessage(error.localizedDescription)
    }

    private func failMessage(_ message: String) {
        errorMessage = message
        stage = .error
        if recordingStatus != .modelUnavailable {
            recordingStatus = .idle
        }
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

    private func startMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateWaveformLevel()
            }
        }
    }

    private func stopMeteringTimer() {
        meteringTimer?.invalidate()
        meteringTimer = nil
    }

    private func updateWaveformLevel() {
        let db = audioRecorder.currentLevel()
        let normalized = max(0, min(1, (CGFloat(db) + 60) / 60))
        let height = 4 + normalized * 48

        if waveformLevels.isEmpty {
            waveformLevels = Array(repeating: 4, count: 37) + [height]
        } else {
            waveformLevels.removeFirst()
            waveformLevels.append(height)
        }
    }

    private func handleRecordingStatusTransition(from oldStatus: RecordingStatus, to newStatus: RecordingStatus) {
        recordingStatusDismissTask?.cancel()
        recordingStatusDismissTask = nil

        switch newStatus {
        case .idle:
            recordingStatusPanel?.orderOut(nil)
        case .recording, .processing, .retrying, .modelUnavailable, .pastedToField, .copiedToClipboard, .copiedRawTranscript:
            showRecordingStatusPanelIfNeeded(allowsUserDismissal: newStatus == .modelUnavailable)
            recordingStatusPanel?.reposition()

            if newStatus == .pastedToField || newStatus == .copiedToClipboard || newStatus == .copiedRawTranscript {
                recordingStatusDismissTask = Task { [weak self] in
                    try? await Task.sleep(for: .seconds(2))
                    await MainActor.run {
                        guard let self, self.recordingStatus == newStatus else { return }
                        self.recordingStatus = .idle
                    }
                }
            }
        }
    }

    private func showRecordingStatusPanelIfNeeded(allowsUserDismissal: Bool) {
        if recordingStatusPanel == nil {
            recordingStatusPanel = RecordingStatusPanel(state: self) { [weak self] in
                guard let self, self.recordingStatus == .modelUnavailable else { return }
                self.recordingStatus = .idle
            }
        }

        recordingStatusPanel?.show(allowsUserDismissal: allowsUserDismissal)
    }

    func openSettings() {
        NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
        NSApp.activate(ignoringOtherApps: true)
        recordingStatus = .idle
    }

    private func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

}
