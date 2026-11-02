// Draws Runwright's app icon and writes a 1024px PNG: a single transit-map
// line on a cream map tile, with three stations. Stages on a pipeline, read
// like a train line.
// Usage: swift scripts/make-icon.swift <output.png> [--light]
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
/// Dark graphite map by default; --light draws the cream paper version.
let light = CommandLine.arguments.contains("--light")

func color(_ rgb: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(srgbRed: CGFloat((rgb >> 16) & 0xFF) / 255, green: CGFloat((rgb >> 8) & 0xFF) / 255,
            blue: CGFloat(rgb & 0xFF) / 255, alpha: alpha)
}

// Drawn top-down (flipped) so coordinates match the SVG the design came from.
let image = NSImage(size: NSSize(width: size, height: size), flipped: true) { _ in
    // macOS icon grid: an 824pt tile centred on the 1024 canvas.
    let tile = NSBezierPath(roundedRect: NSRect(x: 100, y: 100, width: 824, height: 824), xRadius: 185, yRadius: 185)

    NSGraphicsContext.saveGraphicsState()
    let shadow = NSShadow()
    shadow.shadowColor = NSColor.black.withAlphaComponent(0.35)
    shadow.shadowBlurRadius = 26
    shadow.shadowOffset = NSSize(width: 0, height: 12)
    shadow.set()
    color(light ? 0xEDE7DB : 0x141618).setFill()
    tile.fill()
    NSGraphicsContext.restoreGraphicsState()

    // Map paper: cream, or graphite for the dark version, a touch darker
    // towards the bottom.
    let paper = light ? [color(0xF6F2E9), color(0xE3DCCD)] : [color(0x24272B), color(0x0D0E10)]
    NSGradient(colors: paper)!.draw(in: tile, angle: 90)
    if !light {
        // A faint rim so the tile holds its edge in a dark Dock.
        let rim = NSBezierPath(roundedRect: NSRect(x: 102, y: 102, width: 820, height: 820), xRadius: 183, yRadius: 183)
        rim.lineWidth = 4
        NSColor.white.withAlphaComponent(0.12).setStroke()
        rim.stroke()
    }

    // The line.
    let line = NSBezierPath()
    line.move(to: NSPoint(x: 220, y: 640))
    line.line(to: NSPoint(x: 420, y: 640))
    line.line(to: NSPoint(x: 600, y: 400))
    line.line(to: NSPoint(x: 804, y: 400))
    line.lineWidth = 84
    line.lineCapStyle = .round
    line.lineJoinStyle = .round
    color(light ? 0xE2483B : 0xF0564A).setStroke()
    line.stroke()

    // Stations: white with a black ring.
    for p in [NSPoint(x: 220, y: 640), NSPoint(x: 510, y: 520), NSPoint(x: 804, y: 400)] {
        let station = NSBezierPath(ovalIn: NSRect(x: p.x - 46, y: p.y - 46, width: 92, height: 92))
        NSColor.white.setFill()
        station.fill()
        station.lineWidth = 18
        // On graphite the ring takes the tile's colour, so stations sit
        // cut into the line.
        color(light ? 0x1A1A1A : 0x111214).setStroke()
        station.stroke()
    }
    return true
}

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size), bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fatalError("could not render icon") }
try png.write(to: URL(fileURLWithPath: out))
print("wrote \(out)")
