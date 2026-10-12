import AppKit
import Foundation

// Keep the Icon Composer rendering intact, but make the web image opaque so
// GitHub table stripes cannot show through its rounded transparent corners.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
guard let image = NSImage(contentsOf: input),
    let bitmap = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: 1024, pixelsHigh: 1024, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0),
    let context = NSGraphicsContext(bitmapImageRep: bitmap)
else { fatalError("Cannot load Icon Composer preview") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
let rect = NSRect(x: 0, y: 0, width: 1024, height: 1024)
NSColor.white.setFill()
rect.fill()
image.draw(in: rect, from: .zero, operation: .sourceOver, fraction: 1)
NSGraphicsContext.restoreGraphicsState()
guard let png = bitmap.representation(using: .png, properties: [:]) else {
    fatalError("Cannot encode public icon preview")
}
try png.write(to: output)
