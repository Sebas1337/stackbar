// Draws the DMG window's background: an arrow from the app to Applications and a line of text.
// Usage: swiftc -o dmg-background scripts/dmg-background.swift && ./dmg-background <out-dir>
// Writes background.png (1x) and background@2x.png; make-dmg.sh joins them into one TIFF.
// The geometry must match the window bounds and icon positions in make-dmg.sh.
import AppKit

let size = NSSize(width: 540, height: 380)
/// Icon centres, from the top left like Finder's positions: Stackbar.app and Applications.
let appCenter = NSPoint(x: 140, y: 170)
let applicationsCenter = NSPoint(x: 400, y: 170)

func draw(scale: CGFloat, to url: URL) throws {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil,
        pixelsWide: Int(size.width * scale), pixelsHigh: Int(size.height * scale),
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0
    )!
    rep.size = size  // 144 dpi for the 2x image, so tiffutil pairs the two
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    defer { NSGraphicsContext.restoreGraphicsState() }

    // Light background: Finder draws the icon labels in black on it.
    NSGradient(
        starting: NSColor(calibratedWhite: 0.98, alpha: 1),
        ending: NSColor(calibratedWhite: 0.92, alpha: 1)
    )!.draw(in: NSRect(origin: .zero, size: size), angle: -90)

    // AppKit draws from the bottom left; Finder positions count from the top left.
    let y = size.height - appCenter.y
    let start = appCenter.x + 78
    let end = applicationsCenter.x - 78
    let color = NSColor(calibratedWhite: 0.55, alpha: 1)
    color.set()

    let shaft = NSBezierPath()
    shaft.lineWidth = 6
    shaft.lineCapStyle = .round
    shaft.move(to: NSPoint(x: start, y: y))
    shaft.line(to: NSPoint(x: end - 14, y: y))
    shaft.stroke()

    let head = NSBezierPath()
    head.lineWidth = 6
    head.lineCapStyle = .round
    head.lineJoinStyle = .round
    head.move(to: NSPoint(x: end - 22, y: y + 18))
    head.line(to: NSPoint(x: end, y: y))
    head.line(to: NSPoint(x: end - 22, y: y - 18))
    head.stroke()

    let paragraph = NSMutableParagraphStyle()
    paragraph.alignment = .center
    let text = NSAttributedString(
        string: "Drag Stackbar to Applications",
        attributes: [
            .font: NSFont.systemFont(ofSize: 15, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 0.35, alpha: 1),
            .paragraphStyle: paragraph,
        ]
    )
    text.draw(in: NSRect(x: 0, y: 62, width: size.width, height: 24))

    guard let png = rep.representation(using: .png, properties: [:]) else {
        throw CocoaError(.fileWriteUnknown)
    }
    try png.write(to: url)
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: dmg-background <out-dir>\n".utf8))
    exit(2)
}
let folder = URL(fileURLWithPath: arguments[1], isDirectory: true)
do {
    try draw(scale: 1, to: folder.appendingPathComponent("background.png"))
    try draw(scale: 2, to: folder.appendingPathComponent("background@2x.png"))
} catch {
    FileHandle.standardError.write(Data("dmg-background: \(error)\n".utf8))
    exit(1)
}
