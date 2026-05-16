import PureVoiceCore
import SwiftUI

struct MenuBarView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(state.stage.label, systemImage: state.stageIconName)
                .font(.headline)

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
        .frame(width: 260)
    }
}
