import AppKit
import Foundation
import OSLog
import PureVoiceCore
import SwiftUI

private let pipelineLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.adrian.purevoice",
    category: "Pipeline"
)

private let onboardingLogger = Logger(
    subsystem: Bundle.main.bundleIdentifier ?? "com.adrian.purevoice",
    category: "Onboarding"
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

enum PersonaPreviewPhase: Equatable {
    case idle
    case loading
    case complete
    case failed
}

struct PersonaPreviewResult: Equatable {
    var phase: PersonaPreviewPhase = .idle
    var text = ""
    var isStale = false
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
    static let onboardingCompletedDefaultsKey = "hasCompletedOnboarding"

    @Published var stage: AppStage = .idle
    @Published var personas: [Persona] = []
    @Published var personaPromptDrafts: [String: String] = [:]
    @Published var personaPromptSaveStatus: [String: String] = [:]
    @Published var personaPreviewInput = ""
    @Published var personaPreviewResults: [String: PersonaPreviewResult] = [:]
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
    @Published var parakeetHealth = STTHealth(engine: "parakeet", available: false, message: "Not checked")
    @Published var sttInstallInProgress = false
    @Published var sttInstallStatus: String?
    @Published var sttNotice: String?
    @Published var transcriptPreview = ""
    @Published var polishedPreview = ""
    @Published var errorMessage: String?
    @Published var lastPasteStatus: PasteStatus?
    @Published var lastPasteFallbackReason: PasteFallbackReason?
    @Published var availableUpdate: AppUpdateInfo?
    @Published var updateStatus = "Not checked"
    @Published var updateInProgress = false
    @Published var hotkeyBindings: [HotkeyAction: HotkeyBinding] = HotkeyBinding.defaultBindings
    @Published var capturingHotkeyAction: HotkeyAction?
    @Published var hotkeyCaptureStatus: String?
    @Published var recordingMode: RecordingMode = .pushToRecord {
        didSet { saveStringConfig("recording_mode", recordingMode.rawValue) }
    }
    @Published var recordingStatus: RecordingStatus = .idle {
        didSet { handleRecordingStatusTransition(from: oldValue, to: recordingStatus) }
    }
    @Published var waveformLevels: [CGFloat] = Array(repeating: 4, count: 38)

    private let audioRecorder = AudioRecorderService()
    private let appleClient = AppleFoundationModelClient()
    private let releaseClient = GitHubReleaseClient()
    private let updateInstaller = GitHubUpdateInstaller()
    private let pasteService = PasteService()
    private let hotKeyService = HotkeyService()
    private var store: SQLiteStore?
    private var personaStore: PersonaStore?
    private var sttClient: STTHelperClient?
    private var activeAudioURL: URL?
    private var activeRecordingSTTEngine: STTEngine?
    private var originalTarget: FocusTarget?
    private var loaded = false
    private var meteringTimer: Timer?
    private var recordingStatusPanel: RecordingStatusPanel?
    private var settingsWindow: NSWindow?
    private var settingsWindowDelegate: SettingsWindowDelegate?
    private var onboardingWindow: NSWindow?
    private var onboardingWindowDelegate: OnboardingWindowDelegate?
    private var recordingStatusDismissTask: Task<Void, Never>?
    private var personaPromptSaveTasks: [String: Task<Void, Never>] = [:]
    private var personaPreviewTasks: [String: Task<Void, Never>] = [:]
    private var lastPersonaPreviewInput = ""
    private var stalePreviewPersonaIDs = Set<String>()
    private var pushToTalkKeyDown = false
    private var pushToTalkStartedRecording = false
    private var pushToTalkStartTask: Task<Void, Never>?

    init() {
        appleFoundationAvailability = AppleFoundationModelClient.availability
    }

    static func migrateOnboardingSentinelIfNeeded() {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: onboardingCompletedDefaultsKey) == nil else { return }

        if existingDatabaseFileExists() {
            defaults.set(true, forKey: onboardingCompletedDefaultsKey)
        }
    }

    private static func existingDatabaseFileExists() -> Bool {
        let supportDirectory = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        )[0]
            .appendingPathComponent("Pure Voice", isDirectory: true)
        let databaseURL = supportDirectory.appendingPathComponent("pure_voice.sqlite")
        return FileManager.default.fileExists(atPath: databaseURL.path)
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
        switch selectedSTTEngine {
        case .whisper:
            return whisperHealth.available
        case .parakeet:
            return parakeetHealth.available
        }
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
                return "Pure Voice copied this because macOS did not confirm Accessibility control for this build. If Pure Voice is already enabled in System Settings, toggle it off and back on."
            case .targetUnavailable:
                return "Pure Voice copied this because it could not identify the target field. Click the field first, then start recording with the hotkey."
            case .targetActivationFailed:
                return "Pure Voice copied this because it could not bring the original target app back to the front."
            case .focusedInputUnavailable:
                return "Pure Voice copied this because the original app did not expose a focused text field for automatic insertion."
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

    var recordingInstructionText: String {
        switch recordingMode {
        case .pushToRecord:
            return "Stop with \(hotkeyDisplayText(for: .pushToRecordStop))."
        case .pushToTalk:
            return "Release \(hotkeyDisplayText(for: .pushToRecord)) to stop."
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
                nextStep: "Enable Pure Voice in System Settings > Privacy & Security > Accessibility. If it is already enabled, toggle Pure Voice off and back on so macOS refreshes trust for the current build.",
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
            || lowered.contains("parakeet")
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
            let personaStore = PersonaStore(store: store)
            self.personaStore = personaStore
            personas = try store.loadPersonas()
            loadPersonaPromptDrafts(using: personaStore)
            let defaultPersonaID = personas.first(where: \.isDefault)?.id ?? PersonaDefaults.defaultPersonaID
            let storedPersonaID = readStringConfig("active_persona_id") ?? defaultPersonaID
            selectedPersonaID = personas.contains { $0.id == storedPersonaID }
                ? storedPersonaID
                : defaultPersonaID
            if let rawEngine = readStringConfig("stt_engine"),
               let engine = STTEngine(rawValue: rawEngine) {
                selectedSTTEngine = engine
            } else {
                selectedSTTEngine = .whisper
            }
            saveHistory = readBoolConfig("save_history") ?? true
            hotkeyBindings = readHotkeyBindings()
            if let rawRecordingMode = readStringConfig("recording_mode"),
               let mode = RecordingMode(rawValue: rawRecordingMode) {
                recordingMode = mode
            } else {
                recordingMode = .pushToRecord
            }
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
            bindings: hotkeyBindings,
            handler: { [weak self] action, phase in
                Task { @MainActor [weak self] in
                    self?.handleHotkeyEvent(action: action, phase: phase)
                }
            }
        )

        _ = pasteService.hasAccessibilityPermission(prompt: false)
        await refreshAppleFoundationAvailability()
        if UserDefaults.standard.bool(forKey: Self.onboardingCompletedDefaultsKey) {
            await ensureSTTDependencies()
        } else {
            await refreshSTTHealth()
        }
        await checkForUpdates(promptIfAvailable: true)
    }

    func checkForUpdates(promptIfAvailable: Bool = false) async {
        updateStatus = "Checking GitHub releases..."

        do {
            let release = try await releaseClient.fetchLatestRelease()
            let currentVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"

            guard let updateInfo = GitHubUpdateService.updateInfo(
                currentVersion: currentVersion,
                latestRelease: release
            ) else {
                availableUpdate = nil
                updateStatus = "Pure Voice is up to date."
                return
            }

            availableUpdate = updateInfo
            updateStatus = "Pure Voice \(updateInfo.latestVersion) is available."

            if promptIfAvailable {
                promptForUpdate(updateInfo)
            }
        } catch let error as GitHubUpdaterError {
            switch error {
            case .invalidResponse(404):
                availableUpdate = nil
                updateStatus = "No GitHub releases published yet."
            default:
                updateStatus = "Update check failed: \(error.localizedDescription)"
            }
        } catch {
            updateStatus = "Update check failed: \(error.localizedDescription)"
        }
    }

    func installAvailableUpdate() async {
        guard let availableUpdate else { return }
        updateInProgress = true
        updateStatus = "Downloading \(availableUpdate.assetName)..."

        do {
            try await updateInstaller.downloadAndPrepareInstall(availableUpdate)
            updateStatus = "Installing update..."
            NSApp.terminate(nil)
        } catch {
            updateInProgress = false
            updateStatus = "Update failed: \(error.localizedDescription)"
            errorMessage = updateStatus
            stage = .error
        }
    }

    private func promptForUpdate(_ updateInfo: AppUpdateInfo) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Pure Voice \(updateInfo.latestVersion) is available"
        alert.informativeText = "You are running \(updateInfo.currentVersion). Pure Voice can download \(updateInfo.assetName) from GitHub Releases and update itself now."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Update")
        alert.addButton(withTitle: "Later")
        alert.addButton(withTitle: "View Release")

        switch alert.runModal() {
        case .alertFirstButtonReturn:
            Task { await installAvailableUpdate() }
        case .alertThirdButtonReturn:
            NSWorkspace.shared.open(updateInfo.releaseURL)
        default:
            break
        }
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

    func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: Self.onboardingCompletedDefaultsKey)
    }

    func openOnboardingIfNeeded() {
        let completed = UserDefaults.standard.bool(forKey: Self.onboardingCompletedDefaultsKey)
        onboardingLogger.info("openOnboardingIfNeeded completed=\(completed, privacy: .public)")
        guard !completed else { return }

        if onboardingWindow == nil {
            createOnboardingWindow()
        }

        guard let onboardingWindow else { return }
        NSApp.setActivationPolicy(.regular)
        NSApp.unhide(nil)
        NSApp.activate(ignoringOtherApps: true)
        onboardingWindow.level = .modalPanel
        onboardingWindow.collectionBehavior.insert(.moveToActiveSpace)
        onboardingWindow.setIsVisible(true)
        onboardingWindow.makeKeyAndOrderFront(nil)
        onboardingWindow.orderFrontRegardless()
        NSApp.arrangeInFront(nil)
        onboardingWindow.displayIfNeeded()
        onboardingLogger.info("Welcome window ordered front")
    }

    func requestMicrophonePermissionForOnboarding() async -> Bool {
        await audioRecorder.requestPermission()
    }

    func requestAccessibilityPermissionForOnboarding(prompt: Bool) -> Bool {
        pasteService.hasAccessibilityPermission(prompt: prompt)
    }

    func openMicrophonePrivacySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")
    }

    func openAccessibilityPrivacySettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
    }

    func openAppleIntelligenceSettings() {
        openSystemSettingsPane("x-apple.systempreferences:com.apple.Apple-Intelligence-Settings.extension")
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
        Parakeet: \(parakeetHealth.message)
        """
        _ = pasteService.copyToPasteboard(details)
    }

    func copyLatestOutputToClipboard() {
        _ = pasteService.copyToPasteboard(latestOutputText)
        lastPasteStatus = .copied
        lastPasteFallbackReason = PasteFallbackReason.none
        stage = .copied
    }

    func editablePrompt(for persona: Persona) -> String {
        personaPromptDrafts[persona.id]
            ?? (try? personaStore?.editablePrompt(for: persona))
            ?? PersonaStore.defaultPrompt(for: persona.id)
            ?? PersonaStore.stripSharedGuardrail(from: persona.systemPrompt)
    }

    func personaPromptStatus(for persona: Persona) -> String? {
        personaPromptSaveStatus[persona.id]
    }

    func personaPreviewResult(for persona: Persona) -> PersonaPreviewResult {
        personaPreviewResults[persona.id] ?? PersonaPreviewResult()
    }

    func isPersonaPromptCustomized(_ persona: Persona) -> Bool {
        editablePrompt(for: persona) != (PersonaStore.defaultPrompt(for: persona.id) ?? "")
    }

    func updatePersonaPrompt(_ prompt: String, for persona: Persona) {
        let cleaned = PersonaStore.stripSharedGuardrail(from: prompt)
        personaPromptDrafts[persona.id] = cleaned
        personaPromptSaveStatus[persona.id] = "Saving..."
        if !lastPersonaPreviewInput.isEmpty {
            stalePreviewPersonaIDs.insert(persona.id)
            markPersonaPreviewStale(personaID: persona.id)
        }
        personaPromptSaveTasks[persona.id]?.cancel()
        personaPromptSaveTasks[persona.id] = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            await MainActor.run {
                self?.savePersonaPromptDraft(for: persona)
            }
        }
    }

    @discardableResult
    func restoreDefaultPrompt(for persona: Persona) -> Bool {
        guard confirmRestoreDefaultPrompt(for: persona) else { return false }
        personaPromptSaveTasks[persona.id]?.cancel()
        personaPromptSaveTasks[persona.id] = nil

        do {
            try personaStore?.reset(persona: persona)
            personaPromptDrafts[persona.id] = PersonaStore.defaultPrompt(for: persona.id) ?? persona.systemPrompt
            personaPromptSaveStatus[persona.id] = "Restored default"
            stalePreviewPersonaIDs.insert(persona.id)
            markPersonaPreviewStale(personaID: persona.id)
            return true
        } catch {
            personaPromptSaveStatus[persona.id] = "Restore failed: \(error.localizedDescription)"
            return false
        }
    }

    func restoreDefaultPromptAndPreview(for persona: Persona) {
        guard restoreDefaultPrompt(for: persona) else { return }
        guard !personaPreviewInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        runPersonaPreview(for: [persona], input: personaPreviewInput)
    }

    func clearPersonaPreview() {
        personaPreviewInput = ""
        personaPreviewResults = [:]
        lastPersonaPreviewInput = ""
        stalePreviewPersonaIDs.removeAll()
        personaPreviewTasks.values.forEach { $0.cancel() }
        personaPreviewTasks.removeAll()
    }

    func runPersonaPreviewFromButton() {
        let trimmed = personaPreviewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            clearPersonaPreview()
            return
        }

        if trimmed == lastPersonaPreviewInput {
            refreshStalePersonaPreviewIfNeeded()
            return
        }

        lastPersonaPreviewInput = trimmed
        stalePreviewPersonaIDs.removeAll()
        runPersonaPreview(for: personas, input: trimmed)
    }

    func refreshStalePersonaPreviewIfNeeded() {
        let trimmed = personaPreviewInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !stalePreviewPersonaIDs.isEmpty else { return }
        let stalePersonas = personas.filter { stalePreviewPersonaIDs.contains($0.id) }
        runPersonaPreview(for: stalePersonas, input: trimmed)
    }

    private func runPersonaPreview(for personasToPreview: [Persona], input: String) {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        for persona in personasToPreview {
            savePersonaPromptDraft(for: persona)
            stalePreviewPersonaIDs.remove(persona.id)
            personaPreviewTasks[persona.id]?.cancel()
            personaPreviewResults[persona.id] = PersonaPreviewResult(phase: .loading, text: "", isStale: false)

            personaPreviewTasks[persona.id] = Task { [weak self] in
                guard let self else { return }

                do {
                    let prompt = self.promptForPreview(persona)
                    let output = try await self.appleClient.polish(text: trimmed, systemPrompt: prompt)
                    guard !Task.isCancelled else { return }
                    self.personaPreviewResults[persona.id] = PersonaPreviewResult(
                        phase: .complete,
                        text: output,
                        isStale: false
                    )
                } catch {
                    guard !Task.isCancelled else { return }
                    self.personaPreviewResults[persona.id] = PersonaPreviewResult(
                        phase: .failed,
                        text: error.localizedDescription,
                        isStale: false
                    )
                }
            }
        }
    }

    private func promptForPreview(_ persona: Persona) -> String {
        PersonaStore.promptWithGuardrail(editablePrompt(for: persona))
    }

    private func markPersonaPreviewStale(personaID: String) {
        var result = personaPreviewResults[personaID] ?? PersonaPreviewResult()
        result.isStale = result.phase != .idle
        personaPreviewResults[personaID] = result
    }

    func refreshSTTHealth() async {
        guard let sttClient else { return }
        guard !sttInstallInProgress else { return }
        async let whisper = sttClient.health(engine: .whisper)
        async let parakeet = sttClient.health(engine: .parakeet)
        whisperHealth = await whisper
        parakeetHealth = await parakeet
    }

    func sttHealth(for engine: STTEngine) -> STTHealth {
        switch engine {
        case .whisper:
            whisperHealth
        case .parakeet:
            parakeetHealth
        }
    }

    func sttEngineIsAvailable(_ engine: STTEngine) -> Bool {
        sttHealth(for: engine).available
    }

    func selectInstalledSTTEngineFromInstallFlow(_ engine: STTEngine) {
        selectedSTTEngine = engine
        sttNotice = nil
    }

    func displaySTTHealthMessage(for health: STTHealth) -> String {
        Self.userFacingSTTMessage(from: health.message, available: health.available)
    }

    func displaySTTInstallError(from rawMessage: String) -> String {
        Self.userFacingInstallError(from: rawMessage)
    }

    func ensureSTTDependencies() async {
        guard let sttClient else { return }
        guard !sttInstallInProgress else { return }

        async let whisper = sttClient.health(engine: .whisper)
        async let parakeet = sttClient.health(engine: .parakeet)
        let whisperResult = await whisper
        whisperHealth = whisperResult
        parakeetHealth = await parakeet

        guard !whisperResult.available else { return }
        await installSTTDependencies(engine: .whisper)
    }

    func installSTTDependencies(engine: STTEngine = .whisper) async {
        guard let sttClient else { return }
        guard !sttInstallInProgress else { return }

        sttInstallInProgress = true
        sttInstallStatus = "Starting \(engine.displayName) install..."
        setSTTHealth(STTHealth(engine: engine.rawValue, available: false, message: "Installing \(engine.displayName)..."))
        defer {
            sttInstallInProgress = false
            sttInstallStatus = nil
        }

        let health = await sttClient.install(engine: engine) { [weak self] progress in
            Task { @MainActor [weak self] in
                self?.sttInstallStatus = progress
            }
        }
        setSTTHealth(health)

        if health.available {
            if stage == .error,
               errorMessage?.localizedCaseInsensitiveContains("\(engine.displayName) setup failed") == true {
                errorMessage = nil
                stage = .idle
            }
        } else {
            if engine == .whisper {
                failMessage("\(engine.displayName) setup failed: \(health.message)")
            } else {
                sttNotice = "\(engine.displayName) setup failed: \(health.message)"
            }
        }
    }

    func selectSTTEngine(_ engine: STTEngine) async {
        selectedSTTEngine = engine
        sttNotice = nil

        guard engine == .parakeet else { return }
        await refreshSTTHealth()
        guard !parakeetHealth.available else { return }

        if confirmParakeetInstall(reason: "Parakeet needs to be installed before Pure Voice can use it.") {
            await installSTTDependencies(engine: .parakeet)
            if !parakeetHealth.available {
                sttNotice = "Parakeet could not be installed. Pure Voice will use Whisper until Parakeet is resolved."
            }
        } else {
            sttNotice = "Parakeet is selected but not installed. Pure Voice will ask again before recording."
        }
    }

    func hotkeyBinding(for action: HotkeyAction) -> HotkeyBinding {
        hotkeyBindings[action] ?? HotkeyBinding.defaultBindings[action] ?? .defaultPushToRecord
    }

    func hotkeyDisplayText(for action: HotkeyAction) -> String {
        if capturingHotkeyAction == action {
            return "Press shortcut..."
        }
        return hotkeyBinding(for: action).displayString
    }

    func hotkeyWarning(for action: HotkeyAction) -> String? {
        HotkeyConflictDetector.warning(for: hotkeyBinding(for: action))
    }

    func hotkeyUsesDefault(for action: HotkeyAction) -> Bool {
        hotkeyBinding(for: action) == (HotkeyBinding.defaultBindings[action] ?? .defaultPushToRecord)
    }

    func beginHotkeyCapture(for action: HotkeyAction) {
        capturingHotkeyAction = action
        hotkeyCaptureStatus = "Press the new shortcut. You can include multiple keys or mouse buttons. Escape cancels."
        hotKeyService.beginCapture { [weak self] result in
            Task { @MainActor [weak self] in
                guard let self, self.capturingHotkeyAction == action else { return }
                switch result {
                case .captured(let binding):
                    self.setHotkeyBinding(binding, for: action)
                    self.hotkeyCaptureStatus = "\(action.displayName) set to \(binding.displayString)."
                case .cancelled:
                    self.hotkeyCaptureStatus = "Shortcut capture cancelled."
                }
                self.capturingHotkeyAction = nil
            }
        }
    }

    func cancelHotkeyCapture() {
        hotKeyService.cancelCapture()
    }

    func restoreDefaultHotkey(for action: HotkeyAction) {
        let binding = HotkeyBinding.defaultBindings[action] ?? .defaultPushToRecord
        setHotkeyBinding(binding, for: action)
        hotkeyCaptureStatus = "\(action.displayName) restored to \(binding.displayString)."
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

    private func handleHotkeyEvent(action: HotkeyAction, phase: HotkeyPhase) {
        guard capturingHotkeyAction == nil else { return }

        switch (recordingMode, action, phase) {
        case (.pushToRecord, .pushToRecord, .keyDown):
            Task { await startRecordingFromHotKey() }
        case (.pushToRecord, .pushToRecordStop, .keyDown):
            Task { await stopRecordingFromHotKey() }
        case (.pushToTalk, .pushToRecord, .keyDown):
            beginPushToTalkHold()
        case (.pushToTalk, .pushToRecord, .keyUp):
            endPushToTalkHold()
        default:
            return
        }
    }

    private func beginPushToTalkHold() {
        guard !pushToTalkKeyDown else { return }
        pushToTalkKeyDown = true
        pushToTalkStartedRecording = false
        pushToTalkStartTask?.cancel()
        pushToTalkStartTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(1500))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self, self.pushToTalkKeyDown else { return }
                self.pushToTalkStartedRecording = true
                Task { await self.startRecordingFromHotKey() }
            }
        }
    }

    private func endPushToTalkHold() {
        guard pushToTalkKeyDown else { return }
        pushToTalkKeyDown = false
        pushToTalkStartTask?.cancel()
        pushToTalkStartTask = nil

        guard pushToTalkStartedRecording else { return }
        pushToTalkStartedRecording = false
        Task { await stopRecordingFromHotKey() }
    }

    private func resolveSTTEngineForRecording() async -> STTEngine? {
        switch selectedSTTEngine {
        case .whisper:
            guard whisperHealth.available else {
                failMessage("Whisper is not available. Check STT setup.")
                return nil
            }
            return .whisper

        case .parakeet:
            await refreshSTTHealth()
            if parakeetHealth.available {
                sttNotice = nil
                return .parakeet
            }

            guard confirmParakeetInstall(reason: "Parakeet is selected but is not installed yet.") else {
                sttNotice = "Parakeet is selected but not installed. Recording was not started."
                return nil
            }

            await installSTTDependencies(engine: .parakeet)
            if parakeetHealth.available {
                sttNotice = nil
                return .parakeet
            }

            if whisperHealth.available {
                sttNotice = "Parakeet is unavailable, so this recording will use Whisper."
                return .whisper
            }

            failMessage("Parakeet is unavailable and Whisper fallback is not ready.")
            return nil
        }
    }

    func startRecording() async {
        let targetAtGesture = pasteService.captureFocus()
        let micAllowed = await audioRecorder.requestPermission()
        guard micAllowed else {
            fail(AudioRecorderError.microphoneDenied)
            return
        }

        guard let recordingEngine = await resolveSTTEngineForRecording() else {
            return
        }

        do {
            transcriptPreview = ""
            polishedPreview = ""
            errorMessage = nil
            lastPasteStatus = nil
            lastPasteFallbackReason = nil
            originalTarget = targetAtGesture
            activeRecordingSTTEngine = recordingEngine
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
        let recordingEngine = activeRecordingSTTEngine ?? selectedSTTEngine
        defer { activeRecordingSTTEngine = nil }

        let overallStart = Date()
        stage = .transcribing
        recordingStatus = .processing
        var fallbackSTTResult: STTResult?

        do {
            guard let sttClient else {
                throw STTHelperError.helperMissing("stt_helper.py")
            }

            let sttResult = try await transcribeWithFallback(
                audioURL: audioURL,
                preferredEngine: recordingEngine,
                sttClient: sttClient
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

    private func transcribeWithFallback(
        audioURL: URL,
        preferredEngine: STTEngine,
        sttClient: STTHelperClient
    ) async throws -> STTResult {
        pipelineLogger.info("Pipeline transcribe started using \(preferredEngine.rawValue, privacy: .public)")
        do {
            return try await sttClient.transcribe(
                audioURL: audioURL,
                engine: preferredEngine,
                model: nil
            )
        } catch {
            guard preferredEngine == .parakeet else {
                throw error
            }

            pipelineLogger.error("Parakeet transcription failed; trying Whisper fallback: \(error.localizedDescription, privacy: .public)")
            let whisper = await sttClient.health(engine: .whisper)
            whisperHealth = whisper
            guard whisper.available else {
                throw error
            }

            selectedSTTEngine = .whisper
            sttNotice = "Parakeet failed, so Pure Voice switched back to Whisper."
            let fallback = try await sttClient.transcribe(
                audioURL: audioURL,
                engine: .whisper,
                model: nil
            )
            pipelineLogger.info("Whisper fallback transcription succeeded, chars=\(fallback.rawText.count, privacy: .public)")
            return fallback
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
            let systemPrompt = (try? personaStore?.currentPrompt(for: persona))
                ?? PersonaStore.promptWithGuardrail(persona.systemPrompt)
            let polished = try await appleClient.polish(
                text: transcript,
                systemPrompt: systemPrompt
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
                let systemPrompt = (try? personaStore?.currentPrompt(for: persona))
                    ?? PersonaStore.promptWithGuardrail(persona.systemPrompt)
                let polished = try await appleClient.polish(
                    text: transcript,
                    systemPrompt: systemPrompt
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
        pushToTalkKeyDown = false
        pushToTalkStartedRecording = false
        pushToTalkStartTask?.cancel()
        pushToTalkStartTask = nil
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

    private func readHotkeyBindings() -> [HotkeyAction: HotkeyBinding] {
        var bindings = HotkeyBinding.defaultBindings
        for action in configurableHotkeyActions {
            if let binding = readHotkeyBindingConfig(action) {
                bindings[action] = migratedHotkeyBinding(binding, for: action)
            }
        }
        return bindings
    }

    private var configurableHotkeyActions: [HotkeyAction] {
        [.pushToRecord, .pushToRecordStop]
    }

    private func migratedHotkeyBinding(_ binding: HotkeyBinding, for action: HotkeyAction) -> HotkeyBinding {
        switch (action, binding.displayString) {
        case (.pushToRecord, "right ⌘ + right ⌥"):
            return .defaultPushToRecord
        case (.pushToRecordStop, "right ⌘ + right ⌥ + Space"):
            return .defaultPushToRecordStop
        default:
            return binding
        }
    }

    private func readHotkeyBindingConfig(_ action: HotkeyAction) -> HotkeyBinding? {
        guard
            let raw = try? store?.loadConfig(key: hotkeyConfigKey(for: action)),
            let data = raw.data(using: .utf8),
            let value = try? JSONDecoder().decode(HotkeyBinding.self, from: data)
        else {
            return nil
        }
        return value
    }

    private func loadPersonaPromptDrafts(using personaStore: PersonaStore) {
        var drafts: [String: String] = [:]
        for persona in personas {
            drafts[persona.id] = (try? personaStore.editablePrompt(for: persona))
                ?? PersonaStore.defaultPrompt(for: persona.id)
                ?? PersonaStore.stripSharedGuardrail(from: persona.systemPrompt)
        }
        personaPromptDrafts = drafts
    }

    private func savePersonaPromptDraft(for persona: Persona) {
        do {
            try personaStore?.saveOverride(persona: persona, prompt: editablePrompt(for: persona))
            personaPromptSaveStatus[persona.id] = "Saved"
        } catch {
            personaPromptSaveStatus[persona.id] = "Save failed: \(error.localizedDescription)"
        }
    }

    private func saveStringConfig(_ key: String, _ value: String) {
        guard let data = try? JSONEncoder().encode(value), let raw = String(data: data, encoding: .utf8) else { return }
        try? store?.saveConfig(key: key, valueJSON: raw)
    }

    private func saveBoolConfig(_ key: String, _ value: Bool) {
        guard let data = try? JSONEncoder().encode(value), let raw = String(data: data, encoding: .utf8) else { return }
        try? store?.saveConfig(key: key, valueJSON: raw)
    }

    private func setSTTHealth(_ health: STTHealth) {
        switch STTEngine(rawValue: health.engine) {
        case .whisper:
            whisperHealth = health
        case .parakeet:
            parakeetHealth = health
        case nil:
            break
        }
    }

    private static func userFacingSTTMessage(from rawMessage: String, available: Bool) -> String {
        let message = rawMessage.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else {
            return available ? "Ready" : "Not installed"
        }

        let lowered = message.lowercased()
        if available {
            return message
        }

        if lowered.contains("not checked") {
            return "Not checked"
        }
        if lowered.contains("installing") {
            return message
        }
        if lowered.contains("not installed") || lowered.contains("missing") || lowered.contains("not found") {
            return "Not installed"
        }
        if lowered.contains("permission denied") || lowered.contains("read-only") {
            return "Permission needed"
        }
        if lowered.contains("network") || lowered.contains("timed out") || lowered.contains("timeout") {
            return "Download unavailable"
        }
        if message.contains("/") || lowered.contains("stt helper") || lowered.contains("stt_helper.py") {
            return "Setup needs attention"
        }
        return message
    }

    private static func userFacingInstallError(from rawMessage: String) -> String {
        let lowered = rawMessage.lowercased()

        if lowered.contains("network") || lowered.contains("could not reach") || lowered.contains("couldn't reach") {
            return "Pure Voice couldn't reach the download server. Check your internet connection and try again."
        }
        if lowered.contains("timed out") || lowered.contains("timeout") || lowered.contains("interrupted") || lowered.contains("partial") {
            return "The download was interrupted. This usually fixes itself on retry."
        }
        if lowered.contains("no space") || lowered.contains("disk full") || lowered.contains("errno 28") {
            return "Your startup disk is low on space. Free up at least 1 GB and try again."
        }
        if lowered.contains("permission denied") || lowered.contains("read-only") || lowered.contains("errno 13") || lowered.contains("errno 30") {
            return "Pure Voice doesn't have permission to write to Application Support."
        }
        if lowered.contains("checksum") || lowered.contains("verification") || lowered.contains("verify") {
            return "The download didn't complete cleanly. This usually fixes itself on retry."
        }
        return "Something went wrong during installation. Try again, or use Whisper instead."
    }

    private func setHotkeyBinding(_ binding: HotkeyBinding, for action: HotkeyAction) {
        hotkeyBindings[action] = binding
        saveHotkeyBindingConfig(binding, for: action)
        hotKeyService.updateBindings(hotkeyBindings)
    }

    private func saveHotkeyBindingConfig(_ binding: HotkeyBinding, for action: HotkeyAction) {
        guard let data = try? JSONEncoder().encode(binding), let raw = String(data: data, encoding: .utf8) else { return }
        try? store?.saveConfig(key: hotkeyConfigKey(for: action), valueJSON: raw)
    }

    private func hotkeyConfigKey(for action: HotkeyAction) -> String {
        "hotkey_\(action.rawValue)"
    }

    private func confirmParakeetInstall(reason: String) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Install Parakeet?"
        alert.informativeText = "\(reason)\n\nPure Voice will install parakeet-mlx and prepare the selected speech-to-text engine. You can keep using Whisper if you do not want to install it now."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "Install Parakeet")
        alert.addButton(withTitle: "Not Now")
        return alert.runModal() == .alertFirstButtonReturn
    }

    private func confirmRestoreDefaultPrompt(for persona: Persona) -> Bool {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = "Restore \(persona.name) default?"
        alert.informativeText = "This replaces the customized \(persona.name) prompt with the built-in default."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Restore Default")
        alert.addButton(withTitle: "Cancel")
        return alert.runModal() == .alertFirstButtonReturn
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
        let linearLevel = max(0, min(1, (CGFloat(db) + 60) / 60))
        let shapedLevel = pow(linearLevel, 0.72)
        let targetHeight = 4 + shapedLevel * 48
        let previousHeight = waveformLevels.last ?? 4
        let smoothing: CGFloat = targetHeight > previousHeight ? 0.72 : 0.26
        let height = previousHeight + (targetHeight - previousHeight) * smoothing

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
        if settingsWindow == nil {
            createSettingsWindow()
        }

        guard let settingsWindow else { return }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow.makeKeyAndOrderFront(nil)
        settingsWindow.orderFrontRegardless()
        recordingStatus = .idle
    }

    private func createSettingsWindow() {
        let rootView = SettingsView()
            .environmentObject(self)
            .frame(
                minWidth: 560,
                idealWidth: 820,
                maxWidth: .infinity,
                minHeight: 520,
                idealHeight: 760,
                maxHeight: .infinity
            )
            .task { await self.loadIfNeeded() }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 820, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Pure Voice Settings"
        window.identifier = NSUserInterfaceItemIdentifier("PureVoiceSettingsWindow")
        window.contentMinSize = NSSize(width: 560, height: 520)
        window.minSize = NSSize(width: 560, height: 520)
        window.collectionBehavior.insert(.fullScreenNone)
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: rootView)
        window.center()

        let delegate = SettingsWindowDelegate { [weak self] in
            self?.settingsWindow = nil
            self?.settingsWindowDelegate = nil
        }
        window.delegate = delegate
        settingsWindowDelegate = delegate
        settingsWindow = window
    }

    private func createOnboardingWindow() {
        onboardingLogger.info("Creating welcome window")
        let rootView = WelcomeView { [weak self] in
            self?.finishOnboarding()
        }
        .environmentObject(self)
        .frame(width: 640, height: 480)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 640, height: 480),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "Welcome to Pure Voice"
        window.identifier = NSUserInterfaceItemIdentifier("PureVoiceWelcomeWindow")
        window.isReleasedWhenClosed = false
        window.isRestorable = false
        window.standardWindowButton(.closeButton)?.isEnabled = false
        window.contentMinSize = NSSize(width: 640, height: 480)
        window.contentMaxSize = NSSize(width: 640, height: 480)
        window.contentView = NSHostingView(rootView: rootView)
        window.center()

        let delegate = OnboardingWindowDelegate { [weak self] in
            self?.onboardingWindow = nil
            self?.onboardingWindowDelegate = nil
        }
        window.delegate = delegate
        onboardingWindowDelegate = delegate
        onboardingWindow = window
        onboardingLogger.info("Welcome window created")
    }

    private func finishOnboarding() {
        completeOnboarding()
        onboardingWindow?.close()
        onboardingWindow = nil
        onboardingWindowDelegate = nil
        NSApp.activate(ignoringOtherApps: true)
    }

    private func openSystemSettingsPane(_ urlString: String) {
        guard let url = URL(string: urlString) else { return }
        NSWorkspace.shared.open(url)
    }

}

private final class SettingsWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}

private final class OnboardingWindowDelegate: NSObject, NSWindowDelegate {
    private let onClose: () -> Void

    init(onClose: @escaping () -> Void) {
        self.onClose = onClose
    }

    func windowWillClose(_ notification: Notification) {
        onClose()
    }
}
