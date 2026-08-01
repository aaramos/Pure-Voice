import SwiftUI

struct StatusModalView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            waveformRow
            transcriptText
            controlBar
        }
        .padding(.horizontal, 34)
        .padding(.top, 28)
        .padding(.bottom, 22)
        .frame(width: 860)
    }

    private var waveformRow: some View {
        HStack(alignment: .center, spacing: 16) {
            WaveformView(levels: state.waveformLevels, status: state.recordingStatus)
                .frame(maxWidth: .infinity)
                .frame(height: 60)

            if state.recordingStatus == .processing || isRetrying {
                ProgressView()
                    .controlSize(.small)
                    .tint(.secondary)
                    .frame(width: 18, height: 18)
            }
        }
        .frame(height: 62)
    }

    private var transcriptText: some View {
        Text(state.statusModalTranscriptText)
            .font(.system(size: 29, weight: .medium))
            .lineSpacing(3)
            .lineLimit(3)
            .minimumScaleFactor(0.72)
            .foregroundStyle(state.statusModalTranscriptIsPlaceholder ? .secondary : .primary)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
            .animation(.easeOut(duration: 0.16), value: state.statusModalTranscriptText)
    }

    private var controlBar: some View {
        HStack(spacing: 14) {
            Image(systemName: "waveform")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(.secondary)
                .frame(width: 34, height: 34)

            if let controlStatusText {
                Text(controlStatusText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.82)
            }

            Spacer(minLength: 16)

            ControlTextButton("Stop", isEnabled: state.canStopFromStatusModal) {
                Task { await state.stopRecordingFromStatusModal() }
            }
            .keyboardShortcut(.space, modifiers: [])

            KeycapButton("Space", isEnabled: state.canStopFromStatusModal) {
                Task { await state.stopRecordingFromStatusModal() }
            }

            ControlTextButton("Cancel", isEnabled: state.canCancelFromStatusModal) {
                state.cancelRecordingFromStatusModal()
            }
            .keyboardShortcut(.escape, modifiers: [])

            KeycapButton("esc", isEnabled: state.canCancelFromStatusModal) {
                state.cancelRecordingFromStatusModal()
            }
        }
        .padding(.horizontal, 18)
        .frame(height: 58)
        .background(controlBarBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var isRetrying: Bool {
        if case .retrying = state.recordingStatus {
            return true
        }
        return false
    }

    private var controlStatusText: String? {
        switch state.recordingStatus {
        case .recording:
            return nil
        case .processing:
            return "Transcribing"
        case .retrying:
            return "Retrying"
        case .modelUnavailable:
            return "Open settings"
        case .noSpeechDetected, .pastedToField, .copiedToClipboard, .copiedRawTranscript, .idle:
            return nil
        }
    }

    private var controlBarBackground: Color {
        colorScheme == .dark ? Color.white.opacity(0.72) : Color.white.opacity(0.78)
    }
}

private struct ControlTextButton: View {
    var title: String
    var isEnabled: Bool
    var action: () -> Void

    init(_ title: String, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 25, weight: .medium))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.82)
                .frame(minWidth: 68, minHeight: 40)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}

private struct KeycapButton: View {
    var title: String
    var isEnabled: Bool
    var action: () -> Void

    init(_ title: String, isEnabled: Bool, action: @escaping () -> Void) {
        self.title = title
        self.isEnabled = isEnabled
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.72)
                .padding(.horizontal, title.count > 3 ? 13 : 10)
                .frame(minHeight: 38)
                .background(
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.primary.opacity(isEnabled ? 0.075 : 0.04))
                )
                .contentShape(RoundedRectangle(cornerRadius: 9, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
    }
}
