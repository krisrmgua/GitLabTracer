import AppKit

// Native vector artwork, rendered at every standard macOS icon size.
// Icons land beside this script. There is no output-path argument.
let output = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: output.path)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
            bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let transform = AffineTransform(scale: CGFloat(pixels) / 1024)
        (transform as NSAffineTransform).concat()
        let tile = NSBezierPath(roundedRect: NSRect(x: 64, y: 64, width: 896, height: 896), xRadius: 202, yRadius: 202)
        NSGradient(starting: NSColor(srgbRed: 0.14, green: 0.25, blue: 0.36, alpha: 1),
                   ending: NSColor(srgbRed: 0.035, green: 0.07, blue: 0.13, alpha: 1))!.draw(in: tile, angle: -90)
        // Connected deployment nodes echo the app's cyan cluster mark.
        let points: [NSPoint] = [NSPoint(x: 512, y: 736), NSPoint(x: 318, y: 624),
            NSPoint(x: 706, y: 624), NSPoint(x: 512, y: 512), NSPoint(x: 318, y: 400),
            NSPoint(x: 706, y: 400), NSPoint(x: 512, y: 288)]
        let links = NSBezierPath()
        for (a, b) in [(0,1),(0,2),(1,3),(2,3),(3,4),(3,5),(4,6),(5,6)] {
            links.move(to: points[a]); links.line(to: points[b])
        }
        NSColor(srgbRed: 0.2, green: 0.71, blue: 0.86, alpha: 0.45).setStroke()
        links.lineWidth = 28; links.stroke()
        for (index, point) in points.enumerated() {
            (index == 3 ? NSColor.white : NSColor(srgbRed: 0.24, green: 0.81, blue: 0.94, alpha: 1)).setFill()
            NSBezierPath(ovalIn: NSRect(x: point.x - 69, y: point.y - 69, width: 138, height: 138)).fill()
        }
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: output.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
