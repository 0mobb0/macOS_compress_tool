import AppKit
let folder = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
for size in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let pixels = size * scale
        let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        let context = NSGraphicsContext.current!.cgContext
        context.scaleBy(x: CGFloat(pixels) / 1024, y: CGFloat(pixels) / 1024)
        NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.38, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 72, y: 72, width: 880, height: 880), xRadius: 195, yRadius: 195).fill()
        NSColor(calibratedRed: 0.96, green: 0.95, blue: 0.90, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 240, y: 260, width: 544, height: 422), xRadius: 44, yRadius: 44).fill()
        NSBezierPath(roundedRect: NSRect(x: 215, y: 694, width: 594, height: 84), xRadius: 24, yRadius: 24).fill()
        NSColor(calibratedRed: 0.12, green: 0.43, blue: 0.38, alpha: 1).setFill()
        for i in 0..<5 {
            let x = i % 2 == 0 ? 470 : 512
            NSBezierPath(rect: NSRect(x: x, y: 612 - i * 44, width: 42, height: 30)).fill()
        }
        NSBezierPath(roundedRect: NSRect(x: 474, y: 316, width: 78, height: 82), xRadius: 18, yRadius: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        let suffix = scale == 2 ? "@2x" : ""
        try bitmap.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent("icon_\(size)x\(size)\(suffix).png"))
    }
}
