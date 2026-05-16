import PureVoiceCore
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state.stage.label, systemImage: state.stageIconName)
                .font(.headline)

            if state.needsAttention {
                AttentionPanel(guidance: state.attentionGuidance)
                    .environmentObject(state)

                Divider()
            }

            if state.hasLatestOutput {
                LatestOutputPanel()
                    .environmentObject(state)

                Divider()
            }

            Button(state.stage == .recording ? "Stop Recording" : "Start Recording") {
                Task { await state.toggleRecording() }
            }

            Divider()

            Picker("Persona", selection: $state.selectedPersonaID) {
                ForEach(state.personas) { persona in
                    Text(persona.name).tag(persona.id)
                }
            }

            Text("Model: \(state.activeModelLabel)")
                .lineLimit(1)
                .foregroundStyle(.secondary)

            Text("Start: right Command + right Option")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("Stop: right Option")
                .font(.caption)
                .foregroundStyle(.secondary)

            Divider()

            SettingsLink {
                Text("Settings")
            }

            Button("Refresh Health") {
                Task { await state.refreshHealth() }
            }

            Button("Quit Pure Voice") {
                NSApp.terminate(nil)
            }
        }
        .padding(.vertical, 8)
        .frame(width: 340)
    }
}

private struct LatestOutputPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(state.latestOutputTitle, systemImage: state.lastPasteStatus == .pasted ? "checkmark.circle.fill" : "doc.on.clipboard")
                .font(.subheadline.weight(.semibold))

            Text(state.latestOutputInstruction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Text(state.latestOutputText)
                .font(.caption)
                .lineLimit(4)
                .truncationMode(.tail)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)

            Button("Copy Again") {
                state.copyLatestOutputToClipboard()
            }
        }
        .padding(10)
        .background(Color.primary.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

private struct AttentionPanel: View {
    @EnvironmentObject private var state: AppState
    var guidance: AttentionGuidance

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label(guidance.title, systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.red)

            Text(guidance.message)
                .font(.caption)
                .foregroundStyle(.primary)
                .fixedSize(horizontal: false, vertical: true)

            Text(guidance.nextStep)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack {
                Button(guidance.actionTitle) {
                    state.performAttentionAction()
                }

                Button("Copy Details") {
                    state.copyAttentionDetailsToClipboard()
                }
            }
        }
        .padding(10)
        .background(Color.red.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
