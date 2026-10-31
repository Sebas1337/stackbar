// Draws Stackbar's app icon: the stack of the menu bar icon ("rectangle.stack"), drawn here (SF
// Symbols may not be used in app icons), white on a blue squircle (user wish, rc.1 test).
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
    let gradient = CGGradient(colorsSpace: space, colors: [color(0x5B95FF), color(0x2F45CF)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gradient, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 924), options: [])
    // A faint light from the top, like Apple's icons.
    let gloss = CGGradient(colorsSpace: space, colors: [color(0xFFFFFF, 0.18), color(0xFFFFFF, 0)] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(gloss, start: CGPoint(x: 512, y: 100), end: CGPoint(x: 512, y: 520), options: [])
    ctx.restoreGState()

    // The stack: the cards behind as narrower strips above the front card, fading back.
    let strips: [(rect: CGRect, alpha: CGFloat)] = [
        (CGRect(x: 382, y: 274, width: 260, height: 44), 0.5),
        (CGRect(x: 317, y: 338, width: 390, height: 44), 0.75),
    ]
    for strip in strips {
        ctx.setFillColor(color(0xFFFFFF, strip.alpha))
        ctx.addPath(roundedRect(strip.rect, 22))
        ctx.fillPath()
    }
    ctx.saveGState()
    shadow(y: 10, blur: 30, alpha: 0.25)
    ctx.setFillColor(color(0xFFFFFF))
    ctx.addPath(roundedRect(CGRect(x: 252, y: 402, width: 520, height: 348), 76))
    ctx.fillPath()
    ctx.restoreGState()
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
