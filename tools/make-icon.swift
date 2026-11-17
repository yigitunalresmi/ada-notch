// Ada uygulama simgesini üretir.  Kullanım: swift tools/make-icon.swift <çıktı.png>
import AppKit

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext

// macOS simge ızgarası: 824 pt'lik yuvarlak kare, çevresinde boşluk
let inset: CGFloat = 100
let rect = CGRect(x: inset, y: inset, width: size - 2 * inset, height: size - 2 * inset)
let shape = NSBezierPath(roundedRect: rect, xRadius: 186, yRadius: 186)

ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -14), blur: 36, color: NSColor.black.withAlphaComponent(0.35).cgColor)
NSColor.black.setFill()
shape.fill()
ctx.restoreGState()

ctx.saveGState()
shape.addClip()
let colors = [NSColor(red: 0.48, green: 0.36, blue: 1.0, alpha: 1).cgColor, NSColor(red: 0.0, green: 0.83, blue: 1.0, alpha: 1).cgColor]
let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(gradient, start: CGPoint(x: rect.minX, y: rect.maxY), end: CGPoint(x: rect.maxX, y: rect.minY), options: [])

// Üstte çentik
let notchW: CGFloat = 330, notchH: CGFloat = 92
let notch = NSBezierPath()
let nx = rect.midX - notchW / 2, top = rect.maxY
notch.move(to: CGPoint(x: nx, y: top))
notch.line(to: CGPoint(x: nx, y: top - notchH + 36))
notch.curve(to: CGPoint(x: nx + 36, y: top - notchH), controlPoint1: CGPoint(x: nx, y: top - notchH), controlPoint2: CGPoint(x: nx, y: top - notchH))
notch.line(to: CGPoint(x: nx + notchW - 36, y: top - notchH))
notch.curve(to: CGPoint(x: nx + notchW, y: top - notchH + 36), controlPoint1: CGPoint(x: nx + notchW, y: top - notchH), controlPoint2: CGPoint(x: nx + notchW, y: top - notchH))
notch.line(to: CGPoint(x: nx + notchW, y: top))
notch.close()
NSColor.black.setFill()
notch.fill()
ctx.restoreGState()

// Ortada kıvılcım
let config = NSImage.SymbolConfiguration(pointSize: 400, weight: .semibold)
if let symbol = NSImage(systemSymbolName: "sparkle", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
    let tinted = NSImage(size: symbol.size)
    tinted.lockFocus()
    symbol.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
    NSColor.white.set()
    NSRect(origin: .zero, size: symbol.size).fill(using: .sourceAtop)
    tinted.unlockFocus()
    let origin = CGPoint(x: rect.midX - symbol.size.width / 2, y: rect.midY - symbol.size.height / 2 - 30)
    ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 24, color: NSColor.black.withAlphaComponent(0.25).cgColor)
    tinted.draw(at: origin, from: .zero, operation: .sourceOver, fraction: 1)
}
image.unlockFocus()

let rep = NSBitmapImageRep(data: image.tiffRepresentation!)!
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
