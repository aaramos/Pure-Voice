import PureVoiceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        TabView {
            generalTab
                .tabItem { Text("General") }

            recordingTab
                .tabItem { Text("Recording") }
        }
        .padding(20)
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

    private var recordingTab: some View {
        VStack(alignment: .leading, spacing: 18) {
            GroupBox("Recording Mode") {
                VStack(alignment: .leading, spacing: 14) {
                    Picker("Mode", selection: $state.recordingMode) {
                        ForEach(RecordingMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)

                    ForEach(RecordingMode.allCases) { mode in
                        if state.recordingMode == mode {
                            Text(mode.detail)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox("Hotkeys") {
                VStack(alignment: .leading, spacing: 16) {
                    hotkeyRow(.pushToRecord, subtitle: "Start or stop a recording.")
                    Divider()
                    hotkeyRow(.pushToTalk, subtitle: "Reserved for hold-to-talk mode.")

                    Text("Hotkeys are system-wide while Pure Voice is running.")
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

    private func hotkeyRow(_ action: HotkeyAction, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(action.displayName)
                .font(.callout.weight(.semibold))

            HStack(spacing: 10) {
                Text(action == .pushToRecord ? "Start / Stop" : "Activate")
                    .foregroundStyle(.secondary)
                    .frame(width: 82, alignment: .leading)

                Button {
                    state.beginHotkeyCapture(for: action)
                } label: {
                    Text(state.hotkeyDisplayText(for: action))
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(1)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(state.capturingHotkeyAction != nil && state.capturingHotkeyAction != action)

                Button(state.capturingHotkeyAction == action ? "Cancel" : "Record new") {
                    if state.capturingHotkeyAction == action {
                        state.cancelHotkeyCapture()
                    } else {
                        state.beginHotkeyCapture(for: action)
                    }
                }
                .disabled(state.capturingHotkeyAction != nil && state.capturingHotkeyAction != action)
            }

            Text(subtitle)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let warning = state.hotkeyWarning(for: action) {
                Label(warning, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }
        }
    }
}
