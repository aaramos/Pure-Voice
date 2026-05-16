import SwiftUI

struct WaveformView: View {
    var levels: [CGFloat]
    var status: RecordingStatus

    @State private var pulse = false

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(Array(renderedLevels.enumerated()), id: \.offset) { index, level in
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(barColor)
                    .frame(width: 4, height: level)
                    .opacity(barOpacity(index: index))
                    .animation(.easeOut(duration: 0.3), value: level)
                    .animation(
                        .easeInOut(duration: 0.82)
                            .repeatForever(autoreverses: true)
                            .delay(Double(index) * 0.018),
                        value: pulse
                    )
            }
        }
        .frame(height: 60)
        .onAppear {
            pulse = true
        }
    }

    private var renderedLevels: [CGFloat] {
        switch status {
        case .recording, .processing:
            return paddedLevels.map { min(52, max(4, $0)) }
        case .idle, .pastedToField, .copiedToClipboard, .copiedRawTranscript, .retrying, .modelUnavailable:
            return Array(repeating: 4, count: 38)
        }
    }

    private var paddedLevels: [CGFloat] {
        let clamped = Array(levels.suffix(38))
        guard clamped.count < 38 else { return clamped }
        return Array(repeating: 4, count: 38 - clamped.count) + clamped
    }

    private var barColor: Color {
        switch status {
        case .recording, .processing:
            return Color(hex: 0xA78BFA)
        case .idle, .pastedToField, .copiedToClipboard, .copiedRawTranscript, .retrying, .modelUnavailable:
            return Color(nsColor: .secondaryLabelColor)
        }
    }

    private func barOpacity(index: Int) -> Double {
        switch status {
        case .recording:
            guard isSilent else { return 1 }
            return pulse ? 0.36 + Double(index % 7) * 0.045 : 1
        case .processing:
            return 0.38
        case .idle, .pastedToField, .copiedToClipboard, .copiedRawTranscript, .retrying, .modelUnavailable:
            return 0.10
        }
    }

    private var isSilent: Bool {
        paddedLevels.max() ?? 4 <= 8
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
