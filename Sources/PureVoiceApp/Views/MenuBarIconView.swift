import SwiftUI

struct MenuBarIconView: View {
    var isRecording: Bool

    var body: some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            let scale = min(size.width, size.height) / 24
            func s(_ value: CGFloat) -> CGFloat { value * scale }
            let centerX = rect.midX
            let palette = IconPalette(recording: isRecording)

            if isRecording {
                let recordingBadge = Path(ellipseIn: rect.insetBy(dx: s(1.7), dy: s(1.7)))
                context.fill(
                    recordingBadge,
                    with: .linearGradient(
                        Gradient(colors: [palette.badgeTop, palette.badgeBottom]),
                        startPoint: CGPoint(x: rect.midX, y: rect.minY),
                        endPoint: CGPoint(x: rect.midX, y: rect.maxY)
                    )
                )
            }

            context.addFilter(.shadow(color: palette.glow.opacity(0.55), radius: s(1.2), x: 0, y: 0))

            let micRect = CGRect(x: centerX - s(3.8), y: s(3.2), width: s(7.6), height: s(12.0))
            let mic = Path(roundedRect: micRect, cornerRadius: s(3.8))
            context.fill(mic, with: .color(palette.mic))
            context.stroke(mic, with: .color(palette.stroke), lineWidth: s(0.72))

            var stand = Path()
            stand.move(to: CGPoint(x: centerX, y: s(15.3)))
            stand.addLine(to: CGPoint(x: centerX, y: s(19.1)))
            stand.move(to: CGPoint(x: centerX - s(4.7), y: s(19.1)))
            stand.addLine(to: CGPoint(x: centerX + s(4.7), y: s(19.1)))
            context.stroke(stand, with: .color(palette.line), style: StrokeStyle(lineWidth: s(1.35), lineCap: .round))

            var arc = Path()
            arc.addArc(
                center: CGPoint(x: centerX, y: s(10.3)),
                radius: s(6.4),
                startAngle: .degrees(28),
                endAngle: .degrees(152),
                clockwise: false
            )
            context.stroke(arc, with: .color(palette.line.opacity(0.9)), style: StrokeStyle(lineWidth: s(1.45), lineCap: .round))
        }
        .frame(width: 24, height: 24)
        .accessibilityLabel("Pure Voice")
    }
}

private struct IconPalette {
    let badgeTop: Color
    let badgeBottom: Color
    let mic: Color
    let stroke: Color
    let line: Color
    let glow: Color

    init(recording: Bool) {
        if recording {
            badgeTop = Color(red: 1.00, green: 0.68, blue: 0.20)
            badgeBottom = Color(red: 0.95, green: 0.32, blue: 0.06)
            mic = .white
            stroke = .white.opacity(0.92)
            line = .white.opacity(0.96)
            glow = Color(red: 1.00, green: 0.54, blue: 0.14)
        } else {
            badgeTop = .clear
            badgeBottom = .clear
            mic = .white
            stroke = .white.opacity(0.95)
            line = .white.opacity(0.98)
            glow = .white
        }
    }
}
