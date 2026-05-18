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
        let active = status == .recording || status == .processing
        let intensity = active ? max(0.18, liveIntensity) : 0.12
        let amplitude = (active ? 18 : 8) + intensity * 22
        let lineWidth: CGFloat = active ? 4.5 : 3.0

        let mainPath = wavePath(
            width: size.width,
            centerY: centerY,
            amplitude: amplitude,
            phase: phase
        )
        let lowerPath = wavePath(
            width: size.width,
            centerY: centerY + 2.5,
            amplitude: amplitude * 0.56,
            phase: phase + .pi * 0.34
        )

        drawEndpointDots(in: &context, size: size, active: active)

        context.addFilter(.shadow(color: Color(red: 0.22, green: 0.65, blue: 1.0).opacity(active ? 0.55 : 0.18), radius: active ? 7 : 3))
        context.stroke(
            lowerPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.05, green: 0.66, blue: 0.92).opacity(active ? 0.38 : 0.14),
                    Color(red: 0.48, green: 0.62, blue: 1.0).opacity(active ? 0.44 : 0.18),
                    Color(red: 0.68, green: 0.24, blue: 1.0).opacity(active ? 0.38 : 0.14)
                ]),
                startPoint: CGPoint(x: 0, y: centerY),
                endPoint: CGPoint(x: size.width, y: centerY)
            ),
            style: StrokeStyle(lineWidth: lineWidth * 0.72, lineCap: .round, lineJoin: .round)
        )

        context.addFilter(.shadow(color: Color(red: 0.58, green: 0.34, blue: 1.0).opacity(active ? 0.48 : 0.14), radius: active ? 8 : 3))
        context.stroke(
            mainPath,
            with: .linearGradient(
                Gradient(colors: [
                    Color(red: 0.08, green: 0.78, blue: 1.0).opacity(active ? 1 : 0.42),
                    Color.white.opacity(active ? 0.9 : 0.45),
                    Color(red: 0.70, green: 0.30, blue: 1.0).opacity(active ? 1 : 0.42)
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

    private func wavePath(width: CGFloat, centerY: CGFloat, amplitude: CGFloat, phase: CGFloat) -> Path {
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
            let y = centerY + sin(t * .pi * 5.2 + phase) * amplitude * envelope

            if step == 0 {
                path.move(to: CGPoint(x: x, y: y))
            } else {
                path.addLine(to: CGPoint(x: x, y: y))
            }
        }

        return path
    }

    private var liveIntensity: CGFloat {
        let maxLevel = paddedLevels.max() ?? 4
        return max(0, min(1, (maxLevel - 6) / 58))
    }

    private var paddedLevels: [CGFloat] {
        let clamped = Array(levels.suffix(38))
        guard clamped.count < 38 else { return clamped }
        return Array(repeating: 4, count: 38 - clamped.count) + clamped
    }
}
