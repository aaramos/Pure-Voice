import PureVoiceCore
import SwiftUI

struct EngineChoiceScreen: View {
    @Binding var selectedEngine: STTEngine
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            VStack(spacing: 8) {
                Text("Choose how Pure Voice transcribes your speech")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)

                Text("Pure Voice supports two on-device transcription engines. You can switch between them anytime.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: 460)
            }

            HStack(spacing: 16) {
                EngineChoiceCard(
                    engine: .whisper,
                    selectedEngine: $selectedEngine,
                    badge: "Recommended",
                    summary: "Battle-tested, broad language support. Runs on any Apple Silicon Mac.",
                    size: InstallEstimates.whisperSize,
                    time: InstallEstimates.whisperTime
                )

                EngineChoiceCard(
                    engine: .parakeet,
                    selectedEngine: $selectedEngine,
                    badge: "Faster, English",
                    summary: "~2x faster than Whisper for English. Best on Apple Silicon with 16 GB+ RAM.",
                    size: InstallEstimates.parakeetSize,
                    time: InstallEstimates.parakeetTime
                )
            }

            Text("Not sure? Start with Whisper. You can install Parakeet later in Settings.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer(minLength: 0)

            HStack {
                Spacer()
                Button("Continue", action: onContinue)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

private struct EngineChoiceCard: View {
    let engine: STTEngine
    @Binding var selectedEngine: STTEngine
    let badge: String
    let summary: String
    let size: String
    let time: String

    private var isSelected: Bool {
        selectedEngine == engine
    }

    var body: some View {
        Button {
            selectedEngine = engine
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                        .foregroundStyle(isSelected ? Color.accentColor : Color.secondary)
                    Text(engine.displayName)
                        .font(.headline)
                }

                Text(badge)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(engine == .whisper ? .green : .secondary)

                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 0)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Download: \(size)")
                    Text("Setup: \(time)")
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 230, alignment: .topLeading)
            .background(.background, in: RoundedRectangle(cornerRadius: 8))
            .overlay {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.25), lineWidth: isSelected ? 2 : 1)
            }
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}
