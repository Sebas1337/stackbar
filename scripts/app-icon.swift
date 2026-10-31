// Draws Stackbar's app icon: a menu bar with a notch and, hanging from Stackbar's item, the
// dropdown panel with three stacked rows (the "rectangle.stack" idea of the menu bar icon).
// Usage: swiftc -o app-icon scripts/app-icon.swift && ./app-icon <out.iconset>
// Writes every size iconutil needs; build-app.sh turns the folder into AppIcon.icns.
// Coordinates are on a 1024 pt canvas from the top left; the body is Apple's 824 pt squircle area.
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(
        srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
        green: CGFloat((hex >> 8) & 0xFF) / 255,
        blue: CGFloat(hex & 0xFF) / 255,
        alpha: alpha
    )
}

func roundedRect(_ rect: CGRect, _ radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func drawIcon(in ctx: CGContext, pixels: Int) {
    let scale = CGFloat(pixels) / 1024
    // Shadows ignore the transform: offsets and blur are given in pixels, y up.
    func shadow(y: CGFloat, blur: CGFloat, alpha: CGFloat) {
        ctx.setShadow(offset: CGSize(width: 0, height: -y * scale), blur: blur * scale, color: color(0x000000, alpha))
    }
    ctx.translateBy(x: 0, y: CGFloat(pixels))
    ctx.scaleBy(x: scale, y: -scale)

    let body = CGRect(x: 100, y: 100, width: 824, height: 824)
    let bodyPath = roundedRect(body, 186)
    let space = CGColorSpace(name: CGColorSpace.sRGB)!

    // Body: blue to indigo, with a soft drop shadow like system icons.
    ctx.saveGState()
    shadow(y: 12, blur: 28, alpha: 0.3)
    ctx.addPath(bodyPath)
    ctx.setFillColor(color(0x3B5BDB))
    ctx.fillPath()
    ctx.restoreGState()

    ctx.saveGState()
    ctx.addPath(bodyPath)
    ctx.clip()
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x5C8DFF), color(0x3446C7)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])

    // The menu bar: a light band across the top, the notch in its middle.
    ctx.setFillColor(color(0xFFFFFF, 0.24))
    ctx.fill(CGRect(x: 100, y: 100, width: 824, height: 132))
    ctx.setFillColor(color(0x0B1033))
    ctx.addPath(roundedRect(CGRect(x: 392, y: 70, width: 240, height: 112), 40))
    ctx.fillPath()

    // Menu bar items: small dots right of the notch; Stackbar's own item highlighted.
    ctx.setFillColor(color(0xFFFFFF, 0.85))
    for x in [668.0, 842.0] {
        ctx.fillEllipse(in: CGRect(x: x - 22, y: 144, width: 44, height: 44))
    }
    ctx.setFillColor(color(0xFFFFFF, 0.35))
    ctx.addPath(roundedRect(CGRect(x: 715, y: 128, width: 86, height: 76), 22))
    ctx.fillPath()
    ctx.setFillColor(color(0xFFFFFF))
    for (index, y) in [146.0, 162.0, 178.0].enumerated() {
        let inset = CGFloat(2 - index) * 7
        ctx.addPath(roundedRect(CGRect(x: 733 + inset, y: y, width: 50 - 2 * inset, height: 10), 5))
    }
    ctx.fillPath()
    ctx.restoreGState()

    // The dropdown panel under Stackbar's item, with three rows: an item image and its name.
    let panel = CGRect(x: 236, y: 280, width: 552, height: 560)
    ctx.saveGState()
    shadow(y: 18, blur: 40, alpha: 0.35)
    ctx.addPath(roundedRect(panel, 64))
    ctx.setFillColor(color(0xFFFFFF))
    ctx.fillPath()
    ctx.restoreGState()

    let rows: [(icon: UInt32, top: CGFloat)] = [(0xFF9F0A, 330), (0x30D158, 500), (0xFF375F, 670)]
    for (index, row) in rows.enumerated() {
        if index == 0 {
            // The hovered row, like the real panel.
            ctx.setFillColor(color(0x3B5BDB, 0.12))
            ctx.addPath(roundedRect(CGRect(x: 262, y: row.top - 22, width: 500, height: 144), 36))
            ctx.fillPath()
        }
        ctx.setFillColor(color(row.icon))
        ctx.addPath(roundedRect(CGRect(x: 296, y: row.top, width: 100, height: 100), 28))
        ctx.fillPath()
        ctx.setFillColor(color(0x1C1C1E, 0.18))
        ctx.addPath(roundedRect(CGRect(x: 436, y: row.top + 34, width: index == 1 ? 220 : 280, height: 32), 16))
        ctx.fillPath()
    }
}

func writePNG(pixels: Int, to url: URL) throws {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    guard let ctx = CGContext(
        data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0, space: space,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else { throw CocoaError(.fileWriteUnknown) }
    ctx.interpolationQuality = .high
    drawIcon(in: ctx, pixels: pixels)
    guard let image = ctx.makeImage(),
          let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
    else { throw CocoaError(.fileWriteUnknown) }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: app-icon <out.iconset>\n".utf8))
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    for points in [16, 32, 128, 256, 512] {
        try writePNG(pixels: points, to: folder.appendingPathComponent("icon_\(points)x\(points).png"))
        try writePNG(pixels: points * 2, to: folder.appendingPathComponent("icon_\(points)x\(points)@2x.png"))
    }
} catch {
    FileHandle.standardError.write(Data("app-icon: \(error)\n".utf8))
    exit(1)
}
