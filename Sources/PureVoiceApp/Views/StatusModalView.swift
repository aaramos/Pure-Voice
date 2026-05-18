import SwiftUI

struct StatusModalView: View {
    @ObservedObject var state: AppState
    @Environment(\.colorScheme) private var colorScheme
    @State private var recordingDotVisible = true

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 14) {
                WaveformView(levels: state.waveformLevels, status: state.recordingStatus)
                    .frame(width: 263, height: 60)

                Spacer(minLength: 0)

                Text(state.selectedPersona.name)
                    .font(.caption.weight(.semibold))
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(.primary.opacity(colorScheme == .dark ? 0.10 : 0.07), in: Capsule())
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 7) {
                HStack(spacing: 9) {
                    statusGlyph
                    Text(statusTitle)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                }
                .foregroundStyle(pillForeground)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(pillBackground, in: Capsule())

                if let subLabel {
                    if state.recordingStatus == .modelUnavailable {
                        Button {
                            state.openSettings()
                        } label: {
                            Text(subLabel)
                                .font(.caption.weight(.medium))
                                .foregroundStyle(pillForeground)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Text(subLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
        .frame(width: 420)
        .onAppear {
            recordingDotVisible = false
        }
    }

    @ViewBuilder
    private var statusGlyph: some View {
        switch state.recordingStatus {
        case .recording:
            Circle()
                .fill(pillForeground)
                .frame(width: 8, height: 8)
                .opacity(recordingDotVisible ? 1 : 0.28)
                .animation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true), value: recordingDotVisible)
        case .processing:
            ProgressView()
                .controlSize(.small)
                .tint(pillForeground)
                .frame(width: 14, height: 14)
        case .pastedToField:
            Image(systemName: "checkmark.circle.fill")
        case .copiedToClipboard, .copiedRawTranscript:
            Image(systemName: "doc.on.doc.fill")
        case .retrying:
            Image(systemName: "exclamationmark.triangle.fill")
        case .modelUnavailable:
            Image(systemName: "exclamationmark.circle.fill")
        case .idle:
            EmptyView()
        }
    }

    private var statusTitle: String {
        switch state.recordingStatus {
        case .idle:
            return ""
        case .recording:
            return "Recording — press shortcut to stop"
        case .processing:
            return "Transcribing & refining…"
        case .pastedToField:
            return "Pasted into field"
        case .copiedToClipboard:
            return "Copied to clipboard"
        case .copiedRawTranscript:
            return "Copied raw transcript"
        case .retrying:
            return "Model not ready — retrying…"
        case .modelUnavailable:
            return "Model unavailable"
        }
    }

    private var subLabel: String? {
        switch state.recordingStatus {
        case .pastedToField, .copiedToClipboard:
            return "Dismisses in 2s"
        case .copiedRawTranscript:
            return "Polishing failed; dismisses in 2s"
        case .retrying(let attempt):
            return "Retry \(attempt) of 2"
        case .modelUnavailable:
            return "Open settings ↗"
        case .idle, .recording, .processing:
            return nil
        }
    }

    private var pillBackground: Color {
        switch state.recordingStatus {
        case .recording:
            return colorScheme == .dark ? Color(hex: 0x7C3AED).opacity(0.28) : Color(hex: 0xF5F3FF)
        case .processing:
            return colorScheme == .dark ? Color(hex: 0xF59E0B).opacity(0.24) : Color(hex: 0xFFFBEB)
        case .pastedToField:
            return colorScheme == .dark ? Color(hex: 0x65A30D).opacity(0.24) : Color(hex: 0xF0FDF4)
        case .copiedToClipboard, .copiedRawTranscript:
            return colorScheme == .dark ? Color(hex: 0x2563EB).opacity(0.24) : Color(hex: 0xEFF6FF)
        case .retrying, .modelUnavailable:
            return colorScheme == .dark ? Color(hex: 0xEF4444).opacity(0.24) : Color(hex: 0xFEF2F2)
        case .idle:
            return .clear
        }
    }

    private var pillForeground: Color {
        switch state.recordingStatus {
        case .recording:
            return colorScheme == .dark ? Color(hex: 0xC4B8FF) : Color(hex: 0x5B21B6)
        case .processing:
            return colorScheme == .dark ? Color(hex: 0xFAC775) : Color(hex: 0x92400E)
        case .pastedToField:
            return colorScheme == .dark ? Color(hex: 0x97C459) : Color(hex: 0x166534)
        case .copiedToClipboard, .copiedRawTranscript:
            return colorScheme == .dark ? Color(hex: 0x85B7EB) : Color(hex: 0x1D4ED8)
        case .retrying, .modelUnavailable:
            return colorScheme == .dark ? Color(hex: 0xF09595) : Color(hex: 0x991B1B)
        case .idle:
            return .secondary
        }
    }
}

private extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255
        )
    }
}
