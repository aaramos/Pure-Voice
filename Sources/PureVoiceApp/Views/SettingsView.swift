import PureVoiceCore
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            personaSection
            olmxSection
            sttSection
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

    private var olmxSection: some View {
        GroupBox("OLMX Endpoint") {
            VStack(alignment: .leading, spacing: 12) {
                TextField("Base URL", text: $state.endpointURLString)
                    .textFieldStyle(.roundedBorder)

                HStack {
                    SecureField(state.apiKeyPresent ? "Saved API key" : "API key", text: $state.apiKeyInput)
                        .textFieldStyle(.roundedBorder)

                    Button("Save Key") {
                        Task { await state.saveAPIKey() }
                    }
                    .disabled(state.apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }

                HStack {
                    Button("Check Health") {
                        Task { await state.refreshLLMHealth() }
                    }

                    Button("Refresh Models") {
                        Task { await state.refreshModels() }
                    }

                    Text(state.llmStatus)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Picker("Polishing model", selection: $state.selectedModelID) {
                    Text("Select a model").tag("")
                    ForEach(state.models) { model in
                        Text(model.id).tag(model.id)
                    }
                }
                .pickerStyle(.menu)
                .onChange(of: state.selectedModelID) { _, selectedModel in
                    UserDefaults.standard.set(selectedModel, forKey: "selectedOLMXModel")
                }
            }
        }
    }

    private var sttSection: some View {
        GroupBox("Speech To Text") {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Engine", selection: $state.selectedSTTEngine) {
                    Text("Whisper").tag(STTEngine.whisper)
                }
                .pickerStyle(.segmented)

                healthRow("Whisper", health: state.whisperHealth)
                healthRow("Parakeet", health: state.parakeetHealth)

                Button("Refresh STT Health") {
                    Task { await state.refreshSTTHealth() }
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
