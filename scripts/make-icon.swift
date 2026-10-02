import AppKit

// Renders the 1024px app icon on Apple's macOS icon grid:
// violet→cyan squircle, soft top highlight, white "cleaning bubbles" glyph with a drop shadow.
let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

let body = NSRect(x: 100, y: 100, width: 824, height: 824)
let shape = NSBezierPath(roundedRect: body, xRadius: 186, yRadius: 186)

// Outer shadow so the icon sits on the Dock.
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 28, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
NSGradient(colors: [NSColor(srgbRed: 0.47, green: 0.33, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.24, green: 0.52, blue: 1.00, alpha: 1),
                    NSColor(srgbRed: 0.13, green: 0.85, blue: 0.95, alpha: 1)])!
    .draw(in: body, angle: -55)
// Glossy highlight across the top half.
NSGradient(colors: [NSColor.white.withAlphaComponent(0.28), NSColor.white.withAlphaComponent(0)])!
    .draw(in: NSRect(x: 100, y: 512, width: 824, height: 412), angle: -90)
ctx.restoreGState()

// Thin inner border for definition in dark mode.
NSColor.white.withAlphaComponent(0.18).setStroke()
let border = NSBezierPath(roundedRect: body.insetBy(dx: 2, dy: 2), xRadius: 184, yRadius: 184)
border.lineWidth = 4
border.stroke()

let config = NSImage.SymbolConfiguration(pointSize: 440, weight: .medium)
    .applying(.init(paletteColors: [.white, NSColor.white.withAlphaComponent(0.85)]))
if let symbol = NSImage(systemSymbolName: "bubbles.and.sparkles.fill", accessibilityDescription: nil)?
    .withSymbolConfiguration(config) {
    let s = symbol.size
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 30, color: NSColor(srgbRed: 0.1, green: 0.05, blue: 0.4, alpha: 0.45).cgColor)
    symbol.draw(in: NSRect(x: (size - s.width) / 2, y: (size - s.height) / 2 - 10, width: s.width, height: s.height))
    ctx.restoreGState()
}
image.unlockFocus()
let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
