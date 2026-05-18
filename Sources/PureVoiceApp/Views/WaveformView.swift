import SwiftUI

struct WaveformView: View {
    var levels: [CGFloat]
    var status: RecordingStatus

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, size in
                let seconds = timeline.date.timeIntervalSinceReferenceDate
                drawFlowingWave(in: &context, size: size, phase: CGFloat(seconds) * 1.35)
            }
        }
        .frame(height: 64)
    }

    private func drawFlowingWave(in context: inout GraphicsContext, size: CGSize, phase: CGFloat) {
        let rect = CGRect(origin: .zero, size: size)
        let centerY = rect.midY
        let isRecording = status == .recording
        let isProcessing = status == .processing
        let isActive = isRecording || isProcessing
        let intensity = isRecording ? max(0.10, liveIntensity) : (isProcessing ? 0.22 : 0.06)
        let amplitude = isRecording ? 10 + intensity * 34 : (isProcessing ? 12 : 4.5)
        let lineWidth: CGFloat = isActive ? 4.5 : 2.4
        let workingPhase = isProcessing ? phase * 0.58 : phase

        let mainPath = wavePath(
            width: size.width,
            centerY: centerY,
            amplitude: amplitude,
            phase: workingPhase,
            reactive: isRecording
        )
        let lowerPath = wavePath(
            width: size.width,
            centerY: centerY + 2.5,
            amplitude: amplitude * 0.56,
            phase: workingPhase + .pi * 0.34,
            reactive: isRecording
        )

        drawEndpointDots(in: &context, size: size, active: isActive)

        context.addFilter(.shadow(color: Color(red: 0.22, green: 0.65, blue: 1.0).opacity(isActive ? 0.55 : 0.12), radius: isActive ? 7 : 2))
        context.stroke(
            lowerPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.05, green: 0.66, blue: 0.92).opacity(isActive ? 0.38 : 0.10),
                    Color(red: 0.48, green: 0.62, blue: 1.0).opacity(isActive ? 0.44 : 0.12),
                    Color(red: 0.68, green: 0.24, blue: 1.0).opacity(isActive ? 0.38 : 0.10)
                ]),
                startPoint: CGPoint(x: 0, y: centerY),
                endPoint: CGPoint(x: size.width, y: centerY)
            ),
            style: StrokeStyle(lineWidth: lineWidth * 0.72, lineCap: .round, lineJoin: .round)
        )

        context.addFilter(.shadow(color: Color(red: 0.58, green: 0.34, blue: 1.0).opacity(isActive ? 0.48 : 0.10), radius: isActive ? 8 : 2))
        context.stroke(
            mainPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.08, green: 0.78, blue: 1.0).opacity(isActive ? 1 : 0.32),
                    Color.white.opacity(isActive ? 0.9 : 0.32),
                    Color(red: 0.70, green: 0.30, blue: 1.0).opacity(isActive ? 1 : 0.32)
                ]),
                startPoint: CGPoint(x: 0, y: centerY),
                endPoint: CGPoint(x: size.width, y: centerY)
            ),
            style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
        )
    }

    private func drawEndpointDots(in context: inout GraphicsContext, size: CGSize, active: Bool) {
        let centerY = size.height / 2
        let dotColor = active
            ? Color(red: 0.20, green: 0.76, blue: 1.0)
            : Color(nsColor: .secondaryLabelColor)
        let rightColor = active
            ? Color(red: 0.72, green: 0.28, blue: 1.0)
            : Color(nsColor: .secondaryLabelColor)

        for index in 0..<5 {
            let radius = CGFloat(2.0 - Double(index) * 0.18)
            let leftX = CGFloat(index) * 10 + 8
            let rightX = size.width - CGFloat(index) * 10 - 8
            context.fill(
                Path(ellipseIn: CGRect(x: leftX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)),
                with: .color(dotColor.opacity(active ? 0.72 - Double(index) * 0.08 : 0.18))
            )
            context.fill(
                Path(ellipseIn: CGRect(x: rightX - radius, y: centerY - radius, width: radius * 2, height: radius * 2)),
                with: .color(rightColor.opacity(active ? 0.72 - Double(index) * 0.08 : 0.18))
            )
        }
    }

    private func wavePath(width: CGFloat, centerY: CGFloat, amplitude: CGFloat, phase: CGFloat, reactive: Bool) -> Path {
        var path = Path()
        let steps = 120
        let startX: CGFloat = 42
        let endX = max(startX + 1, width - 42)

        for step in 0...steps {
            let t = CGFloat(step) / CGFloat(steps)
            let x = startX + (endX - startX) * t
            let leftEnvelope = exp(-pow((t - 0.34) / 0.20, 2))
            let rightEnvelope = exp(-pow((t - 0.70) / 0.24, 2))
            let envelope = max(leftEnvelope, rightEnvelope)
            let liveEnvelope = reactive ? (0.28 + levelEnvelope(at: t) * 1.15) : 1
            let y = centerY + sin(t * .pi * 5.2 + phase) * amplitude * envelope * liveEnvelope

            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private var liveIntensity: CGFloat {
        let recent = paddedLevels.suffix(12)
        let average = recent.reduce(CGFloat.zero, +) / CGFloat(max(1, recent.count))
        let peak = recent.max() ?? 4
        let blended = average * 0.45 + peak * 0.55
        return normalizedLevel(blended)
    }

    private var paddedLevels: [CGFloat] {
        let clamped = Array(levels.suffix(38))
        guard clamped.count < 38 else { return clamped }
        return Array(repeating: 4, count: 38 - clamped.count) + clamped
    }

    private func levelEnvelope(at position: CGFloat) -> CGFloat {
        let samples = paddedLevels
        guard samples.count > 1 else { return 0 }

        let scaledIndex = max(0, min(CGFloat(samples.count - 1), position * CGFloat(samples.count - 1)))
        let lowerIndex = Int(floor(scaledIndex))
        let upperIndex = min(samples.count - 1, lowerIndex + 1)
        let mix = scaledIndex - CGFloat(lowerIndex)
        let interpolated = samples[lowerIndex] + (samples[upperIndex] - samples[lowerIndex]) * mix
        return normalizedLevel(interpolated)
    }

    private func normalizedLevel(_ height: CGFloat) -> CGFloat {
        max(0, min(1, (height - 4) / 48))
    }
}
