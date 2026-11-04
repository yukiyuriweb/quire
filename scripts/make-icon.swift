// Renders the app icon: swift scripts/make-icon.swift <out.png>
// An open book over the edges of its gathered sheets (a quire), with a ribbon marker.
import AppKit

let size: CGFloat = 1024
let out = CommandLine.arguments.dropFirst().first ?? "icon.png"

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(size), pixelsHigh: Int(size),
                           bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                           colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext

func rgb(_ hex: UInt32) -> CGColor {
    CGColor(red: CGFloat(hex >> 16 & 0xff) / 255, green: CGFloat(hex >> 8 & 0xff) / 255,
            blue: CGFloat(hex & 0xff) / 255, alpha: 1)
}

func gradient(_ top: UInt32, _ bottom: UInt32) -> CGGradient {
    CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [rgb(top), rgb(bottom)] as CFArray, locations: [0, 1])!
}

let ink: UInt32 = 0x2B2A5C

// Rounded-square body with a drop shadow, per the macOS icon grid (824pt body on 1024 canvas).
let body = CGRect(x: 100, y: 100, width: 824, height: 824)
let bodyPath = CGPath(roundedRect: body, cornerWidth: 185, cornerHeight: 185, transform: nil)
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: CGColor(gray: 0, alpha: 0.35))
ctx.addPath(bodyPath)
ctx.setFillColor(rgb(ink))
ctx.fillPath()
ctx.restoreGState()

ctx.saveGState()
ctx.addPath(bodyPath)
ctx.clip()
ctx.drawLinearGradient(gradient(0x5B5BB5, ink), start: CGPoint(x: 0, y: 924), end: CGPoint(x: 0, y: 100), options: [])
ctx.restoreGState()

// One page of the open book: its outer edge sags a little, its top and bottom curve into the spine.
let spine = CGPoint(x: 512, y: 300)
func page(side: CGFloat, drop: CGFloat) -> CGPath {
    let p = CGMutablePath()
    let outer = 512 + side * 300
    p.move(to: CGPoint(x: spine.x, y: spine.y - drop))
    p.addCurve(to: CGPoint(x: outer, y: 330 - drop), control1: CGPoint(x: 512 + side * 90, y: 360 - drop),
               control2: CGPoint(x: 512 + side * 200, y: 330 - drop))
    p.addLine(to: CGPoint(x: outer, y: 700 - drop))
    p.addCurve(to: CGPoint(x: spine.x, y: 680 - drop), control1: CGPoint(x: 512 + side * 200, y: 700 - drop),
               control2: CGPoint(x: 512 + side * 90, y: 730 - drop))
    p.closeSubpath()
    return p
}

// The gathered sheets underneath, drawn as page edges stepping down.
for k in (1...3).reversed() {
    let drop = CGFloat(k) * 16
    for side: CGFloat in [-1, 1] {
        ctx.addPath(page(side: side, drop: drop))
        ctx.setFillColor(rgb(k % 2 == 0 ? 0xE6E2D6 : 0xD2CDBE))
        ctx.fillPath()
    }
}

// The open spread, with a soft shadow toward the spine.
for side: CGFloat in [-1, 1] {
    let path = page(side: side, drop: 0)
    ctx.saveGState()
    ctx.setShadow(offset: CGSize(width: 0, height: -6), blur: 14, color: CGColor(gray: 0, alpha: 0.2))
    ctx.addPath(path)
    ctx.setFillColor(rgb(0xFBF8F0))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(path)
    ctx.clip()
    let toSpine = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(),
                             colors: [CGColor(gray: 0, alpha: 0), CGColor(gray: 0, alpha: 0.14)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(toSpine, start: CGPoint(x: 512 + side * 140, y: 0), end: CGPoint(x: 512, y: 0), options: [])

    // Lines of text, kept few and thick so they survive small sizes.
    ctx.setFillColor(rgb(0xC9C4D8))
    for row in 0..<5 {
        let y = 600 - CGFloat(row) * 58
        let inner: CGFloat = 70, outerInset: CGFloat = 50
        let width = 300 - inner - outerInset - (row == 4 ? 80 : 0)
        let x = side > 0 ? 512 + inner : 512 - inner - width
        ctx.addPath(CGPath(roundedRect: CGRect(x: x, y: y, width: width, height: 20), cornerWidth: 10, cornerHeight: 10, transform: nil))
        ctx.fillPath()
    }
    ctx.restoreGState()
}

// Ribbon marker hanging from the top of the spine.
let ribbon = CGMutablePath()
ribbon.move(to: CGPoint(x: 560, y: 700))
ribbon.addLine(to: CGPoint(x: 610, y: 700))
ribbon.addLine(to: CGPoint(x: 610, y: 440))
ribbon.addLine(to: CGPoint(x: 585, y: 470))
ribbon.addLine(to: CGPoint(x: 560, y: 440))
ribbon.closeSubpath()
ctx.saveGState()
ctx.setShadow(offset: CGSize(width: 0, height: -4), blur: 8, color: CGColor(gray: 0, alpha: 0.25))
ctx.addPath(ribbon)
ctx.setFillColor(rgb(0xD9433B))
ctx.fillPath()
ctx.restoreGState()

NSGraphicsContext.current = nil
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
