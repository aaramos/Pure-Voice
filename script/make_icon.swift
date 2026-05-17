import AppKit
import Foundation

let root = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let resources = root.appendingPathComponent("Sources/PureVoiceApp/Resources")
let previewURL = resources.appendingPathComponent("PureVoiceIcon.png")
let iconsetURL = resources.appendingPathComponent("PureVoice.iconset")
let icnsURL = resources.appendingPathComponent("PureVoice.icns")

try? FileManager.default.removeItem(at: iconsetURL)
try FileManager.default.createDirectory(at: resources, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

func drawIcon(size: CGFloat) -> NSImage {
    let image = NSImage(size: NSSize(width: size, height: size))
    image.lockFocus()

    guard let context = NSGraphicsContext.current?.cgContext else {
        image.unlockFocus()
        return image
    }

    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)

    let rect = CGRect(x: 0, y: 0, width: size, height: size)
    let scale = size / 1024.0
    func s(_ value: CGFloat) -> CGFloat { value * scale }

    let shadowRect = rect.insetBy(dx: s(8), dy: s(10))
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: s(224), yRadius: s(224)).cgPath
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s(18)), blur: s(50), color: NSColor.black.withAlphaComponent(0.56).cgColor)
    context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
    context.addPath(shadowPath)
    context.fillPath()
    context.restoreGState()

    let tileRect = rect.insetBy(dx: s(0), dy: s(0))
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: s(232), yRadius: s(232)).cgPath
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.025, green: 0.028, blue: 0.034, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.038, green: 0.047, blue: 0.070, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.012, green: 0.013, blue: 0.018, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
        options: []
    )

    context.setBlendMode(.screen)
    drawGlow(
        in: context,
        center: CGPoint(x: s(454), y: s(522)),
        radius: s(360),
        color: NSColor(calibratedRed: 0.10, green: 0.72, blue: 0.95, alpha: 0.22)
    )
    drawGlow(
        in: context,
        center: CGPoint(x: s(650), y: s(518)),
        radius: s(340),
        color: NSColor(calibratedRed: 0.56, green: 0.22, blue: 1.0, alpha: 0.20)
    )
    context.setBlendMode(.normal)

    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.setLineWidth(s(10))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.13).cgColor)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.clip()
    drawRibbonSet(in: context, size: size)
    drawCentralSpark(in: context, scale: scale)
    context.restoreGState()

    image.unlockFocus()
    return image
}

func drawGlow(in context: CGContext, center: CGPoint, radius: CGFloat, color: NSColor) {
    let gradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            color.cgColor,
            color.withAlphaComponent(0.05).cgColor,
            NSColor.clear.cgColor
        ] as CFArray,
        locations: [0.0, 0.54, 1.0]
    )!
    context.drawRadialGradient(
        gradient,
        startCenter: center,
        startRadius: 0,
        endCenter: center,
        endRadius: radius,
        options: []
    )
}

func drawRibbonSet(in context: CGContext, size: CGFloat) {
    let scale = size / 1024.0
    func s(_ value: CGFloat) -> CGFloat { value * scale }
    let centerY = s(506)
    let xStart = s(-76)
    let xEnd = s(1100)
    let colors = [
        NSColor(calibratedRed: 0.13, green: 0.86, blue: 1.0, alpha: 0.92),
        NSColor(calibratedRed: 0.42, green: 0.68, blue: 1.0, alpha: 0.98),
        NSColor(calibratedRed: 0.78, green: 0.28, blue: 1.0, alpha: 0.92)
    ]

    for layer in 0..<8 {
        let yOffset = s(CGFloat(layer - 3) * 24)
        let amp = s(88 + CGFloat(layer % 3) * 20)
        let alpha = 0.10 + CGFloat(7 - layer) * 0.035
        let phase = CGFloat(layer) * 0.52
        let path = flowingPath(
            xStart: xStart,
            xEnd: xEnd,
            centerY: centerY + yOffset,
            amplitude: amp,
            phase: phase,
            scale: scale
        )

        context.saveGState()
        context.setLineCap(.round)
        context.setLineJoin(.round)
        context.setLineWidth(s(layer == 3 ? 11 : 5))
        context.setShadow(offset: .zero, blur: s(18), color: colors[layer % colors.count].withAlphaComponent(0.28).cgColor)
        context.addPath(path)
        context.replacePathWithStrokedPath()
        context.clip()

        let gradient = CGGradient(
            colorsSpace: CGColorSpaceCreateDeviceRGB(),
            colors: [
                colors[0].withAlphaComponent(alpha).cgColor,
                NSColor.white.withAlphaComponent(alpha + 0.18).cgColor,
                colors[2].withAlphaComponent(alpha).cgColor
            ] as CFArray,
            locations: [0.0, 0.48, 1.0]
        )!
        context.drawLinearGradient(
            gradient,
            start: CGPoint(x: xStart, y: centerY),
            end: CGPoint(x: xEnd, y: centerY),
            options: []
        )
        context.restoreGState()
    }

    let mainPath = flowingPath(
        xStart: xStart,
        xEnd: xEnd,
        centerY: centerY,
        amplitude: s(80),
        phase: 0.15,
        scale: scale
    )
    context.saveGState()
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.setLineWidth(s(17))
    context.setShadow(offset: .zero, blur: s(28), color: NSColor(calibratedRed: 0.32, green: 0.76, blue: 1.0, alpha: 0.48).cgColor)
    context.addPath(mainPath)
    context.replacePathWithStrokedPath()
    context.clip()
    let mainGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.10, green: 0.78, blue: 1.0, alpha: 1).cgColor,
            NSColor.white.withAlphaComponent(0.95).cgColor,
            NSColor(calibratedRed: 0.76, green: 0.30, blue: 1.0, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.48, 1.0]
    )!
    context.drawLinearGradient(
        mainGradient,
        start: CGPoint(x: xStart, y: centerY),
        end: CGPoint(x: xEnd, y: centerY),
        options: []
    )
    context.restoreGState()
}

func flowingPath(
    xStart: CGFloat,
    xEnd: CGFloat,
    centerY: CGFloat,
    amplitude: CGFloat,
    phase: CGFloat,
    scale: CGFloat
) -> CGPath {
    let path = CGMutablePath()
    let steps = 150
    for step in 0...steps {
        let t = CGFloat(step) / CGFloat(steps)
        let x = xStart + (xEnd - xStart) * t
        let leftEnvelope = exp(-pow((t - 0.37) / 0.20, 2))
        let rightEnvelope = exp(-pow((t - 0.68) / 0.24, 2))
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

func drawCentralSpark(in context: CGContext, scale: CGFloat) {
    func s(_ value: CGFloat) -> CGFloat { value * scale }
    let center = CGPoint(x: s(512), y: s(508))

    context.saveGState()
    context.setBlendMode(.screen)
    drawGlow(
        in: context,
        center: center,
        radius: s(150),
        color: NSColor(calibratedRed: 0.55, green: 0.90, blue: 1.0, alpha: 0.52)
    )
    context.restoreGState()

    context.saveGState()
    context.setLineCap(.round)
    context.setStrokeColor(NSColor(calibratedRed: 0.70, green: 0.94, blue: 1.0, alpha: 0.88).cgColor)
    context.setLineWidth(s(7))
    let vertical = CGMutablePath()
    vertical.move(to: CGPoint(x: center.x, y: center.y - s(180)))
    vertical.addLine(to: CGPoint(x: center.x, y: center.y + s(184)))
    context.addPath(vertical)
    context.strokePath()
    context.restoreGState()

    context.saveGState()
    context.setFillColor(NSColor.white.withAlphaComponent(0.96).cgColor)
    context.setShadow(offset: .zero, blur: s(22), color: NSColor(calibratedRed: 0.36, green: 0.82, blue: 1.0, alpha: 0.9).cgColor)
    context.fillEllipse(in: CGRect(x: center.x - s(26), y: center.y - s(26), width: s(52), height: s(52)))
    context.restoreGState()
}

func savePNG(_ image: NSImage, to url: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let data = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "PureVoiceIcon", code: 1)
    }
    try data.write(to: url)
}

func resamplePNG(at url: URL, pixels: Int) throws {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/sips")
    process.arguments = ["-z", "\(pixels)", "\(pixels)", url.path]
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "PureVoiceIcon", code: Int(process.terminationStatus))
    }
}

let sizes: [(String, CGFloat)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024)
]

try savePNG(drawIcon(size: 1024), to: previewURL)
try resamplePNG(at: previewURL, pixels: 1024)

for (name, size) in sizes {
    let url = iconsetURL.appendingPathComponent(name)
    try savePNG(drawIcon(size: size), to: url)
    try resamplePNG(at: url, pixels: Int(size))
}

let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
process.arguments = ["-c", "icns", iconsetURL.path, "-o", icnsURL.path]
try process.run()
process.waitUntilExit()

guard process.terminationStatus == 0 else {
    throw NSError(domain: "PureVoiceIcon", code: Int(process.terminationStatus))
}

print("Wrote \(icnsURL.path)")
print("Wrote \(previewURL.path)")

extension NSBezierPath {
    var cgPath: CGPath {
        let path = CGMutablePath()
        var points = [NSPoint](repeating: .zero, count: 3)

        for index in 0..<elementCount {
            switch element(at: index, associatedPoints: &points) {
            case .moveTo:
                path.move(to: points[0])
            case .lineTo:
                path.addLine(to: points[0])
            case .curveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .cubicCurveTo:
                path.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo:
                path.addQuadCurve(to: points[1], control: points[0])
            case .closePath:
                path.closeSubpath()
            @unknown default:
                break
            }
        }

        return path
    }
}
