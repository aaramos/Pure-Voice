import PureVoiceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            personaSection
            appleIntelligenceSection
            sttSection
            updateSection
            privacySection
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
                healthRow("Whisper", health: state.whisperHealth)

                HStack {
                    if state.sttInstallInProgress {
                        ProgressView()
                            .controlSize(.small)
                        Text("Installing Whisper...")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    Button("Refresh") {
                        Task { await state.refreshSTTHealth() }
                    }
                    .disabled(state.sttInstallInProgress)

                    if !state.whisperHealth.available {
                        Button("Install Whisper") {
                            Task { await state.installSTTDependencies() }
                        }
                        .disabled(state.sttInstallInProgress)
                    }
                }
            }
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
}
