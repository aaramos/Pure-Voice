import PureVoiceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab: SettingsTab = .general
    @State private var pendingSTTInstallEngine: STTEngine?
    @State private var activeSTTInstallEngine: STTEngine?
    @State private var sttInstallFeedback: STTInstallFeedback?
    @State private var sttToastMessage: String?
    @State private var sttToastDismissTask: Task<Void, Never>?

    var body: some View {
        TabView(selection: $selectedTab) {
            generalTab
                .tabItem { Text("General") }
                .tag(SettingsTab.general)

            recordingTab
                .tabItem { Text("Recording") }
                .tag(SettingsTab.recording)

            advancedTab
                .tabItem { Text("Advanced") }
                .tag(SettingsTab.advanced)

            previewTab
                .tabItem { Text("Preview") }
                .tag(SettingsTab.preview)
        }
        .padding(20)
        .onChange(of: selectedTab) { _, newValue in
            if newValue == .preview {
                state.refreshStalePersonaPreviewIfNeeded()
            }
        }
        .overlay(alignment: .bottom) {
            if let sttToastMessage {
                Text(sttToastMessage)
                    .font(.callout.weight(.medium))
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 12, y: 4)
                    .padding(.bottom, 4)
            }
        }
    }

    private var generalTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            personaSection
            appleIntelligenceSection
            sttSection
            updateSection
            privacySection
        }
    }

    private var advancedTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Persona Prompts")
                        .font(.headline)
                    Text("Edit the instruction sent to the polishing model for each persona.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                ForEach(state.personas) { persona in
                    personaPromptEditor(for: persona)
                }

                GroupBox("Shared Guardrail") {
                    Text(PersonaStore.sharedGuardrail)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var previewTab: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Test your personas against sample text.")
                    .font(.headline)

                TextEditor(text: $state.personaPreviewInput)
                    .font(.body)
                    .frame(height: 128)

                HStack {
                    Spacer()
                    Button("Clear") {
                        state.clearPersonaPreview()
                    }
                    .disabled(state.personaPreviewInput.isEmpty && state.personaPreviewResults.isEmpty)

                    Button("Preview") {
                        state.runPersonaPreviewFromButton()
                    }
                    .keyboardShortcut(.return, modifiers: [.command])
                    .disabled(state.personaPreviewInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                ForEach(state.personas) { persona in
                    personaPreviewBlock(for: persona)
                }

                Label(
                    "Preview uses text input only. Results may differ slightly from live recording polish.",
                    systemImage: "info.circle"
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var recordingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Recording Mode") {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(RecordingMode.allCases) { mode in
                        Button {
                            state.recordingMode = mode
                        } label: {
                            HStack(alignment: .top, spacing: 10) {
                                Image(systemName: state.recordingMode == mode ? "largecircle.fill.circle" : "circle")
                                    .foregroundStyle(state.recordingMode == mode ? Color.accentColor : Color.secondary)
                                    .frame(width: 18)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(mode.displayName)
                                        .font(.callout.weight(.semibold))
                                    Text(mode.detail)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                        .fixedSize(horizontal: false, vertical: true)
                                }

                                Spacer(minLength: 0)
                            }
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Hotkeys") {
                VStack(alignment: .leading, spacing: 10) {
                    switch state.recordingMode {
                    case .pushToRecord:
                        hotkeyRow(.pushToRecord, label: "Start")
                        Divider()
                        hotkeyRow(.pushToRecordStop, label: "Stop")
                    case .pushToTalk:
                        pushToTalkHotkeySummary
                    }

                    Text(hotkeyFooterText)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let status = state.hotkeyCaptureStatus {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            Spacer(minLength: 0)
        }
    }

    private var pushToTalkHotkeySummary: some View {
        HStack(spacing: 10) {
            Text("Hold")
                .foregroundStyle(.secondary)
                .frame(width: 50, alignment: .leading)

            Text(state.hotkeyDisplayText(for: .pushToRecord))
                .font(.system(.body, design: .monospaced))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)

            Text("1.5 sec")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(.secondary.opacity(0.12), in: Capsule())
        }
    }

    private var hotkeyFooterText: String {
        switch state.recordingMode {
        case .pushToRecord:
            "Start and Stop are system-wide while Pure Voice is running."
        case .pushToTalk:
            "Push to Talk uses the Start shortcut. Hold for 1.5 seconds to begin, release to stop."
        }
    }

    private var personaSection: some View {
        GroupBox("Persona") {
            Picker("Active persona", selection: $state.selectedPersonaID) {
                ForEach(state.personas) { persona in
                    Text(persona.name).tag(persona.id)
                }
            }
            .pickerStyle(.menu)
        }
    }

    private var appleIntelligenceSection: some View {
        GroupBox("Polishing") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: state.appleFoundationAvailability == .available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(state.appleFoundationAvailability == .available ? .green : .orange)

                    Text("Apple On-Device")

                    Spacer()

                    Text(state.appleFoundationStatusText)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .font(.callout)
            }
        }
    }

    private var sttSection: some View {
        GroupBox("Speech To Text") {
            VStack(alignment: .leading, spacing: 12) {
                if let activeSTTInstallEngine {
                    STTInstallView(engine: activeSTTInstallEngine) { result in
                        handleSettingsInstallCompletion(result, engine: activeSTTInstallEngine)
                    }
                    .frame(height: 280)
                } else if let pendingSTTInstallEngine {
                    sttInstallConfirmationPanel(for: pendingSTTInstallEngine)
                } else {
                    sttEngineChoices
                }

                if let notice = state.sttNotice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if activeSTTInstallEngine == nil, pendingSTTInstallEngine == nil {
                    sttInstallFeedbackView
                    sttTechnicalDetailsDisclosure
                }

                HStack {
                    if state.sttInstallInProgress, activeSTTInstallEngine == nil {
                        ProgressView()
                            .controlSize(.small)
                        Text(state.sttInstallStatus ?? "Installing...")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh") {
                        Task { await state.refreshSTTHealth() }
                    }
                    .disabled(state.sttInstallInProgress)
                }
            }
        }
    }

    private var sttEngineChoices: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Engine")
                .font(.caption)
                .foregroundStyle(.secondary)

            ForEach(STTEngine.allCases) { engine in
                sttEngineChoiceRow(for: engine)
            }
        }
    }

    private func sttEngineChoiceRow(for engine: STTEngine) -> some View {
        let health = state.sttHealth(for: engine)
        let isSelected = state.selectedSTTEngine == engine
        let status = sttStatus(for: health)

        return Button {
            chooseSTTEngine(engine)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    .frame(width: 18)

                Text(engine.displayName)
                    .font(.callout.weight(.semibold))

                switch status {
                case .available:
                    if !isSelected {
                        Text("available")
                            .foregroundStyle(.secondary)
                    }
                case .notInstalled:
                    Text("not installed")
                        .foregroundStyle(.secondary)
                    Text("Install")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(Color.accentColor)
                case .attention(let message):
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(message)
                        .foregroundStyle(.secondary)
                }

                Spacer()
            }
            .padding(.vertical, 5)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(state.sttInstallInProgress)
    }

    private func sttInstallConfirmationPanel(for engine: STTEngine) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Install \(engine.displayName)?")
                .font(.headline)

            Text("\(engine.displayName) isn't installed yet. Pure Voice needs to download \(installSize(for: engine)). Installation takes \(installTime(for: engine)) on a typical connection.")
                .fixedSize(horizontal: false, vertical: true)

            Text("\(state.selectedSTTEngine.displayName) will remain your transcription engine if you cancel.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel") {
                    pendingSTTInstallEngine = nil
                }
                Button("Install \(engine.displayName)") {
                    sttInstallFeedback = nil
                    activeSTTInstallEngine = engine
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .background(.secondary.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private var sttInstallFeedbackView: some View {
        if let sttInstallFeedback {
            HStack(spacing: 6) {
                Text(sttInstallFeedback.message)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Button("Try again") {
                    pendingSTTInstallEngine = sttInstallFeedback.engine
                    self.sttInstallFeedback = nil
                }
                .font(.caption)
                .buttonStyle(.link)
            }
        }
    }

    @ViewBuilder
    private var sttTechnicalDetailsDisclosure: some View {
        if shouldShowSTTTechnicalDetails {
            DisclosureGroup("Technical details") {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Whisper: \(state.whisperHealth.message)")
                    Text("Parakeet: \(state.parakeetHealth.message)")
                }
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .font(.caption)
        }
    }

    private var shouldShowSTTTechnicalDetails: Bool {
        [state.whisperHealth, state.parakeetHealth].contains { health in
            !health.available && state.displaySTTHealthMessage(for: health) != health.message
        }
    }

    private func chooseSTTEngine(_ engine: STTEngine) {
        sttInstallFeedback = nil
        guard state.selectedSTTEngine != engine || !state.sttEngineIsAvailable(engine) else { return }

        if state.sttEngineIsAvailable(engine) {
            pendingSTTInstallEngine = nil
            state.selectInstalledSTTEngineFromInstallFlow(engine)
        } else {
            pendingSTTInstallEngine = engine
        }
    }

    private func handleSettingsInstallCompletion(_ result: Result<Void, Error>, engine: STTEngine) {
        activeSTTInstallEngine = nil
        pendingSTTInstallEngine = nil

        switch result {
        case .success:
            state.selectInstalledSTTEngineFromInstallFlow(engine)
            sttInstallFeedback = nil
            showSTTToast("\(engine.displayName) is now your transcription engine.")
        case .failure:
            state.selectInstalledSTTEngineFromInstallFlow(.whisper)
            sttInstallFeedback = .failed(engine)
        }
    }

    private func showSTTToast(_ message: String) {
        sttToastDismissTask?.cancel()
        sttToastMessage = message
        sttToastDismissTask = Task {
            try? await Task.sleep(for: .seconds(4))
            await MainActor.run {
                sttToastMessage = nil
            }
        }
    }

    private func sttStatus(for health: STTHealth) -> STTStatus {
        if health.available {
            return .available
        }

        let message = state.displaySTTHealthMessage(for: health)
        if message == "Not installed" || message == "Not checked" {
            return .notInstalled
        }
        return .attention(message)
    }

    private func installSize(for engine: STTEngine) -> String {
        switch engine {
        case .whisper:
            InstallEstimates.whisperSize
        case .parakeet:
            InstallEstimates.parakeetSize
        }
    }

    private func installTime(for engine: STTEngine) -> String {
        switch engine {
        case .whisper:
            InstallEstimates.whisperTime
        case .parakeet:
            InstallEstimates.parakeetTime
        }
    }

    private var updateSection: some View {
        GroupBox("Updates") {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: state.availableUpdate == nil ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .foregroundStyle(state.availableUpdate == nil ? .green : .blue)

                    Text(state.updateStatus)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer()
                }

                HStack {
                    Button("Check For Updates") {
                        Task { await state.checkForUpdates() }
                    }
                    .disabled(state.updateInProgress)

                    if state.availableUpdate != nil {
                        Button(state.updateInProgress ? "Updating..." : "Update Now") {
                            Task { await state.installAvailableUpdate() }
                        }
                        .disabled(state.updateInProgress)
                    }
                }
            }
        }
    }

    private var privacySection: some View {
        GroupBox("Privacy") {
            VStack(alignment: .leading, spacing: 8) {
                Toggle("Save raw and polished transcript history locally", isOn: $state.saveHistory)
                Text("Raw audio is temporary and is deleted after successful transcription.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func healthRow(_ label: String, health: STTHealth) -> some View {
        HStack {
            Image(systemName: health.available ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(health.available ? .green : .orange)
            Text(label)
            Spacer()
            Text(health.message)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        }
        .font(.callout)
    }

    private func hotkeyRow(_ action: HotkeyAction, label: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 10) {
                Text(label)
                    .foregroundStyle(.secondary)
                    .frame(width: 50, alignment: .leading)

                Button {
                    state.beginHotkeyCapture(for: action)
                } label: {
                    Text(state.hotkeyDisplayText(for: action))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(state.capturingHotkeyAction != nil && state.capturingHotkeyAction != action)

                Button(state.capturingHotkeyAction == action ? "Cancel" : "Change") {
                    if state.capturingHotkeyAction == action {
                        state.cancelHotkeyCapture()
                    } else {
                        state.beginHotkeyCapture(for: action)
                    }
                }
                .disabled(state.capturingHotkeyAction != nil && state.capturingHotkeyAction != action)

                if !state.hotkeyUsesDefault(for: action) {
                    Button("Restore Default") {
                        state.restoreDefaultHotkey(for: action)
                    }
                    .disabled(state.capturingHotkeyAction != nil)
                }
            }

            if let warning = state.hotkeyWarning(for: action) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }

    private func personaPromptEditor(for persona: Persona) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(persona.name)
                        .font(.callout.weight(.semibold))

                    if state.isPersonaPromptCustomized(persona) {
                        Text("Customized")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())

                        Button("Restore Default") {
                            state.restoreDefaultPrompt(for: persona)
                        }
                    }

                    Spacer()

                    if let status = state.personaPromptStatus(for: persona) {
                        Text(status)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                TextEditor(text: Binding(
                    get: { state.editablePrompt(for: persona) },
                    set: { state.updatePersonaPrompt($0, for: persona) }
                ))
                .font(.system(.callout, design: .monospaced))
                .frame(minHeight: 92)
            }
        }
    }

    private func personaPreviewBlock(for persona: Persona) -> some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(persona.name)
                        .font(.callout.weight(.semibold))

                    if state.isPersonaPromptCustomized(persona) {
                        Text("Customized")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(.secondary.opacity(0.12), in: Capsule())

                        Button("Restore Default") {
                            state.restoreDefaultPromptAndPreview(for: persona)
                        }
                    }

                    Spacer()

                    if state.personaPreviewResult(for: persona).isStale {
                        Text("Out of date")
                            .font(.caption)
                            .foregroundStyle(.orange)
                    }
                }

                personaPreviewContent(for: persona)
            }
        }
    }

    @ViewBuilder
    private func personaPreviewContent(for persona: Persona) -> some View {
        let result = state.personaPreviewResult(for: persona)

        switch result.phase {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView()
                    .controlSize(.small)
                Text("Loading...")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
        case .complete:
            Text(result.text)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        case .failed:
            Text(result.text)
                .foregroundStyle(.red)
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private enum SettingsTab: Hashable {
    case general
    case recording
    case advanced
    case preview
}

private enum STTStatus {
    case available
    case notInstalled
    case attention(String)
}

private enum STTInstallFeedback: Equatable {
    case canceled(STTEngine)
    case failed(STTEngine)

    var engine: STTEngine {
        switch self {
        case .canceled(let engine), .failed(let engine):
            engine
        }
    }

    var message: String {
        switch self {
        case .canceled(let engine):
            "\(engine.displayName) install canceled."
        case .failed(let engine):
            "\(engine.displayName) install failed."
        }
    }
}
