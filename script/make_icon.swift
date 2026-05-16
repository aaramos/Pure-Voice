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

    let shadowRect = rect.insetBy(dx: s(64), dy: s(54))
    let shadowPath = NSBezierPath(roundedRect: shadowRect, xRadius: s(220), yRadius: s(220)).cgPath
    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -s(24)), blur: s(54), color: NSColor.black.withAlphaComponent(0.35).cgColor)
    context.setFillColor(NSColor.black.withAlphaComponent(0.18).cgColor)
    context.addPath(shadowPath)
    context.fillPath()
    context.restoreGState()

    let tileRect = rect.insetBy(dx: s(74), dy: s(74))
    let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: s(214), yRadius: s(214)).cgPath
    context.saveGState()
    context.addPath(tilePath)
    context.clip()

    let background = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.04, green: 0.08, blue: 0.12, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.02, green: 0.22, blue: 0.27, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.05, green: 0.35, blue: 0.36, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 0.56, 1.0]
    )!
    context.drawLinearGradient(
        background,
        start: CGPoint(x: tileRect.minX, y: tileRect.maxY),
        end: CGPoint(x: tileRect.maxX, y: tileRect.minY),
        options: []
    )

    let glow = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.34, green: 1.0, blue: 0.86, alpha: 0.42).cgColor,
            NSColor(calibratedRed: 0.12, green: 0.52, blue: 0.54, alpha: 0.04).cgColor,
            NSColor.clear.cgColor
        ] as CFArray,
        locations: [0.0, 0.45, 1.0]
    )!
    context.drawRadialGradient(
        glow,
        startCenter: CGPoint(x: s(364), y: s(658)),
        startRadius: s(18),
        endCenter: CGPoint(x: s(364), y: s(658)),
        endRadius: s(420),
        options: []
    )

    context.restoreGState()

    context.saveGState()
    context.addPath(tilePath)
    context.setLineWidth(s(10))
    context.setStrokeColor(NSColor.white.withAlphaComponent(0.22).cgColor)
    context.strokePath()
    context.restoreGState()

    let micCapsule = CGRect(x: s(274), y: s(252), width: s(214), height: s(508))
    let micPath = NSBezierPath(roundedRect: micCapsule, xRadius: s(103), yRadius: s(103)).cgPath
    context.saveGState()
    context.setShadow(offset: .zero, blur: s(26), color: NSColor(calibratedRed: 0.32, green: 1, blue: 0.86, alpha: 0.38).cgColor)
    context.setFillColor(NSColor(calibratedRed: 0.80, green: 1.0, blue: 0.95, alpha: 0.94).cgColor)
    context.addPath(micPath)
    context.fillPath()
    context.restoreGState()

    let innerCapsule = CGRect(x: s(322), y: s(318), width: s(118), height: s(376))
    let innerPath = NSBezierPath(roundedRect: innerCapsule, xRadius: s(61), yRadius: s(61)).cgPath
    context.saveGState()
    context.addPath(innerPath)
    context.clip()
    let innerGradient = CGGradient(
        colorsSpace: CGColorSpaceCreateDeviceRGB(),
        colors: [
            NSColor(calibratedRed: 0.02, green: 0.26, blue: 0.29, alpha: 1).cgColor,
            NSColor(calibratedRed: 0.08, green: 0.52, blue: 0.48, alpha: 1).cgColor
        ] as CFArray,
        locations: [0.0, 1.0]
    )!
    context.drawLinearGradient(
        innerGradient,
        start: CGPoint(x: innerCapsule.minX, y: innerCapsule.maxY),
        end: CGPoint(x: innerCapsule.maxX, y: innerCapsule.minY),
        options: []
    )
    context.restoreGState()

    context.saveGState()
    context.setShadow(offset: .zero, blur: s(28), color: NSColor(calibratedRed: 0.42, green: 1.0, blue: 0.90, alpha: 0.40).cgColor)
    context.setFillColor(NSColor(calibratedRed: 0.70, green: 1.0, blue: 0.90, alpha: 0.96).cgColor)
    let bars: [(CGFloat, CGFloat, CGFloat)] = [
        (s(552), s(412), s(190)),
        (s(622), s(328), s(358)),
        (s(694), s(258), s(500)),
        (s(766), s(344), s(326)),
        (s(836), s(426), s(164))
    ]
    for (x, y, height) in bars {
        let barRect = CGRect(x: x, y: y, width: s(50), height: height)
        context.addPath(NSBezierPath(roundedRect: barRect, xRadius: s(25), yRadius: s(25)).cgPath)
        context.fillPath()
    }
    context.restoreGState()

    let stem = CGMutablePath()
    stem.move(to: CGPoint(x: s(382), y: s(230)))
    stem.addLine(to: CGPoint(x: s(382), y: s(174)))
    stem.move(to: CGPoint(x: s(302), y: s(174)))
    stem.addLine(to: CGPoint(x: s(462), y: s(174)))
    context.saveGState()
    context.setLineCap(.round)
    context.setStrokeColor(NSColor(calibratedRed: 0.80, green: 1.0, blue: 0.95, alpha: 0.9).cgColor)
    context.setLineWidth(s(46))
    context.addPath(stem)
    context.strokePath()
    context.restoreGState()

    func sparkle(center: CGPoint, radius: CGFloat, color: NSColor) {
        let path = CGMutablePath()
        path.move(to: CGPoint(x: center.x, y: center.y + radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + radius * 0.18, y: center.y + radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x + radius * 0.18, y: center.y - radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - radius * 0.18, y: center.y - radius * 0.18))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x - radius * 0.18, y: center.y + radius * 0.18))
        path.closeSubpath()

        context.saveGState()
        context.setShadow(offset: .zero, blur: radius * 0.5, color: color.withAlphaComponent(0.48).cgColor)
        context.setFillColor(color.cgColor)
        context.addPath(path)
        context.fillPath()
        context.restoreGState()
    }

    sparkle(center: CGPoint(x: s(748), y: s(746)), radius: s(76), color: NSColor(calibratedRed: 1.0, green: 0.86, blue: 0.50, alpha: 0.95))
    sparkle(center: CGPoint(x: s(660), y: s(780)), radius: s(24), color: NSColor(calibratedRed: 0.98, green: 1.0, blue: 0.82, alpha: 0.9))

    image.unlockFocus()
    return image
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

for (name, size) in sizes {
    try savePNG(drawIcon(size: size), to: iconsetURL.appendingPathComponent(name))
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
