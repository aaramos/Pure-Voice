import SwiftUI

struct MainWindowView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        NavigationSplitView {
            List {
                Label("Setup", systemImage: "gearshape")
                    .tag("setup")
                Label("Preview", systemImage: "text.alignleft")
                    .tag("preview")
            }
            .listStyle(.sidebar)
            .frame(minWidth: 150)
        } detail: {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    HeaderView()
                    SettingsView()
                    PreviewPanel()
                }
                .padding(24)
                .frame(maxWidth: 760, alignment: .leading)
            }
        }
    }
}

private struct HeaderView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: state.stageIconName)
                .font(.system(size: 30))
                .foregroundStyle(state.stage == .error ? .red : .accentColor)
                .frame(width: 42, height: 42)

            VStack(alignment: .leading, spacing: 4) {
                Text("Pure Voice")
                    .font(.largeTitle.weight(.semibold))
                Text("Start with right Command + right Option. Stop with right Option.")
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button(state.stage == .recording ? "Stop" : "Record") {
                Task { await state.toggleRecording() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
    }
}

private struct PreviewPanel: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Latest Output")
                .font(.title3.weight(.semibold))

            if let error = state.errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Label(state.attentionGuidance.title, systemImage: "exclamationmark.triangle.fill")
                        .font(.headline)
                        .foregroundStyle(.red)

                    Text(error)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(state.attentionGuidance.nextStep)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack {
                        Button(state.attentionGuidance.actionTitle) {
                            state.performAttentionAction()
                        }

                        Button("Copy Details") {
                            state.copyAttentionDetailsToClipboard()
                        }
                    }
                }
                .padding(12)
                .background(Color.red.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            LabeledContent("Raw transcript") {
                Text(state.transcriptPreview.isEmpty ? "No transcript yet." : state.transcriptPreview)
                    .foregroundStyle(state.transcriptPreview.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            LabeledContent("Polished text") {
                Text(state.polishedPreview.isEmpty ? "No polished output yet." : state.polishedPreview)
                    .foregroundStyle(state.polishedPreview.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(16)
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
