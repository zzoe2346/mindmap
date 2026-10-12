import AppKit
import Foundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    guard
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4,
            hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
        let context = NSGraphicsContext(bitmapImageRep: bitmap)
    else { fatalError("bitmap context") }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let scale = Double(size) / 1024
    let transform = NSAffineTransform()
    transform.scale(by: scale)
    transform.concat()
    NSColor.white.setFill()
    NSBezierPath(roundedRect: NSRect(x: 42, y: 42, width: 940, height: 940), xRadius: 205, yRadius: 205)
        .fill()
    let branches: [(NSPoint, NSColor)] = [
        (NSPoint(x: 735, y: 735), .systemIndigo), (NSPoint(x: 770, y: 485), .systemTeal),
        (NSPoint(x: 715, y: 250), .systemOrange),
    ]
    for (end, color) in branches {
        let p = NSBezierPath()
        p.move(to: NSPoint(x: 320, y: 512))
        p.curve(to: end, controlPoint1: NSPoint(x: 535, y: 512), controlPoint2: NSPoint(x: 520, y: end.y))
        color.setStroke()
        p.lineWidth = 32
        p.lineCapStyle = .round
        p.stroke()
        color.setFill()
        NSBezierPath(
            roundedRect: NSRect(x: end.x - 90, y: end.y - 50, width: 175, height: 100), xRadius: 28,
            yRadius: 28
        ).fill()
    }
    NSColor(calibratedRed: 0.13, green: 0.15, blue: 0.22, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 155, y: 415, width: 250, height: 194), xRadius: 56, yRadius: 56)
        .fill()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = bitmap.representation(using: .png, properties: [:]) else {
        fatalError("icon encoding failed")
    }
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try png.write(to: output.appendingPathComponent(name)) }
}

// Package PNG representations in the standard ICNS container without external dependencies.
if CommandLine.arguments.count > 2 {
    var chunks = Data()
    func number(_ value: Int) -> Data {
        var value = UInt32(value).bigEndian
        return withUnsafeBytes(of: &value) { Data($0) }
    }
    for (tag, name) in [
        ("icp4", "icon_16x16.png"), ("icp5", "icon_32x32.png"),
        ("icp6", "icon_32x32@2x.png"), ("ic07", "icon_128x128.png"),
        ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"),
        ("ic10", "icon_512x512@2x.png"),
    ] {
        let data = try Data(contentsOf: output.appendingPathComponent(name))
        chunks.append(Data(tag.utf8))
        chunks.append(number(data.count + 8))
        chunks.append(data)
    }
    var container = Data("icns".utf8)
    container.append(number(chunks.count + 8))
    container.append(chunks)
    try container.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
}
