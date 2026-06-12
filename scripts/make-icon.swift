// Generates Glance/AppIcon.iconset PNGs. Run: swift scripts/make-icon.swift
// Then: iconutil -c icns Glance/AppIcon.iconset -o Glance/AppIcon.icns
import AppKit

func srgb(_ hex: UInt32, _ alpha: CGFloat = 1) -> NSColor {
    NSColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func makeMaster() -> NSImage {
    let canvas: CGFloat = 1024
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.lockFocus()

    // Standard macOS icon grid: 824pt squircle centered on a 1024 canvas
    let squircleRect = NSRect(x: 100, y: 100, width: 824, height: 824)
    let squircle = NSBezierPath(roundedRect: squircleRect, xRadius: 185, yRadius: 185)

    NSGradient(colors: [srgb(0x232E3B), srgb(0x141C26)])!.draw(in: squircle, angle: -90)

    // Subtle top inner highlight
    squircle.addClip()
    let highlight = NSBezierPath(roundedRect: NSRect(x: 100, y: 620, width: 824, height: 304), xRadius: 185, yRadius: 185)
    srgb(0xFFFFFF, 0.05).setFill()
    highlight.fill()

    // "Today" header pill
    let header = NSBezierPath(roundedRect: NSRect(x: 240, y: 700, width: 210, height: 58), xRadius: 29, yRadius: 29)
    srgb(0xFFFFFF, 0.85).setFill()
    header.fill()

    // Agenda bars — teal, purple, coral (the mockup's calendar colors)
    let bars: [(color: UInt32, y: CGFloat, width: CGFloat)] = [
        (0x4FD1C5, 540, 430),
        (0xA78BFA, 400, 544),
        (0xFB7185, 260, 336),
    ]
    for bar in bars {
        let path = NSBezierPath(
            roundedRect: NSRect(x: 240, y: bar.y, width: bar.width, height: 96),
            xRadius: 48, yRadius: 48
        )
        srgb(bar.color).setFill()
        path.fill()
    }

    image.unlockFocus()
    return image
}

func writePNG(_ master: NSImage, pixels: Int, to url: URL) {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = NSSize(width: pixels, height: pixels)
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    master.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: url)
}

let master = makeMaster()
let iconset = URL(fileURLWithPath: "Glance/AppIcon.iconset")
try? FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for size in [16, 32, 128, 256, 512] {
    writePNG(master, pixels: size, to: iconset.appendingPathComponent("icon_\(size)x\(size).png"))
    writePNG(master, pixels: size * 2, to: iconset.appendingPathComponent("icon_\(size)x\(size)@2x.png"))
}
print("Wrote \(iconset.path)")
