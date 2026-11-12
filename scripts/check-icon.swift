// Fails unless macOS resolves the bundle's own icon (the violet monogram), not the generic app icon.
// Usage: swift scripts/check-icon.swift path/to/ReplyAI.app
import AppKit

let path = CommandLine.arguments[1]
let icon = NSWorkspace.shared.icon(forFile: path)
let side = 64
guard let bitmap = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8, samplesPerPixel: 4,
    hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
), let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
    print("Could not create a bitmap to inspect the icon.")
    exit(2)
}
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
icon.draw(in: NSRect(x: 0, y: 0, width: side, height: side))
NSGraphicsContext.restoreGraphicsState()

guard let center = bitmap.colorAt(x: side / 2, y: side / 2) else { exit(2) }
let (red, green, blue) = (center.redComponent, center.greenComponent, center.blueComponent)
print(String(format: "center pixel r=%.2f g=%.2f b=%.2f", red, green, blue))
// The monogram's stroke crosses the center in violet; the generic icon is pale gray there.
if blue > 0.75, red < 0.65, green < 0.55 {
    print("Custom icon resolved.")
} else {
    print("Generic or unexpected icon.")
    exit(1)
}
