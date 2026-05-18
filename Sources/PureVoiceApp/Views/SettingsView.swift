import PureVoiceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState
    @State private var selectedTab: SettingsTab = .general

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
                    .frame(minHeight: 96)

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
                HStack(spacing: 12) {
                    Text("Engine")
                        .foregroundStyle(.secondary)
                        .frame(width: 70, alignment: .leading)

                    ForEach(STTEngine.allCases) { engine in
                        Button {
                            Task { await state.selectSTTEngine(engine) }
                        } label: {
                            Label(
                                engine.displayName,
                                systemImage: state.selectedSTTEngine == engine ? "largecircle.fill.circle" : "circle"
                            )
                        }
                        .buttonStyle(.plain)
                        .disabled(state.sttInstallInProgress)
                    }
                }

                healthRow("Whisper", health: state.whisperHealth)
                healthRow("Parakeet", health: state.parakeetHealth)

                if let notice = state.sttNotice {
                    Label(notice, systemImage: "info.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                HStack {
                    if state.sttInstallInProgress {
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

                    if selectedEngineNeedsInstall {
                        Button("Install \(state.selectedSTTEngine.displayName)") {
                            Task { await state.installSTTDependencies(engine: state.selectedSTTEngine) }
                        }
                        .disabled(state.sttInstallInProgress)
                    }
                }
            }
        }
    }

    private var selectedEngineNeedsInstall: Bool {
        switch state.selectedSTTEngine {
        case .whisper:
            return !state.whisperHealth.available
        case .parakeet:
            return !state.parakeetHealth.available
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
