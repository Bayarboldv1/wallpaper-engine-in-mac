import AppKit

let output = CommandLine.arguments[1]
let manager = FileManager.default
try manager.createDirectory(atPath: output, withIntermediateDirectories: true)
for size in [16, 32, 64, 128, 256, 512, 1024] {
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
    let scale = CGFloat(size) / 1024
    let transform = AffineTransform(scaleByX: scale, byY: scale)
    (transform as NSAffineTransform).concat()
    let box = NSRect(x: 72, y: 72, width: 880, height: 880)
    let shape = NSBezierPath(roundedRect: box, xRadius: 196, yRadius: 196)
    NSGradient(starting: NSColor(srgbRed: 0.13, green: 0.25, blue: 0.24, alpha: 1), ending: NSColor(srgbRed: 0.035, green: 0.09, blue: 0.11, alpha: 1))!.draw(in: shape, angle: -65)
    NSGraphicsContext.saveGraphicsState()
    shape.addClip()
    for line in 0..<26 {
        let path = NSBezierPath()
        for point in 0...80 {
            let x = CGFloat(point) / 80 * 1024
            let y = 540 + sin(x / 1024 * 5.4 + CGFloat(line) * 0.037) * 170 + CGFloat(line) * 5
            if point == 0 { path.move(to: NSPoint(x: x, y: y)) } else { path.line(to: NSPoint(x: x, y: y)) }
        }
        NSColor(srgbRed: 0.62, green: 0.97, blue: 0.76, alpha: 0.035 + Double(line % 6) * 0.023).setStroke()
        path.lineWidth = 12
        path.stroke()
    }
    NSColor(srgbRed: 0.77, green: 0.98, blue: 0.83, alpha: 1).setStroke()
    let sun = NSBezierPath()
    sun.appendArc(withCenter: NSPoint(x: 512, y: 402), radius: 135, startAngle: 0, endAngle: 180, clockwise: false)
    sun.lineWidth = 31
    sun.lineCapStyle = .round
    sun.stroke()
    for (y, inset) in [(402.0, 260.0), (334.0, 316.0), (269.0, 395.0)] {
        let line = NSBezierPath()
        line.move(to: NSPoint(x: inset, y: y)); line.line(to: NSPoint(x: 1024 - inset, y: y))
        line.lineWidth = 25; line.lineCapStyle = .round; line.stroke()
    }
    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.restoreGraphicsState()
    let data = bitmap.representation(using: .png, properties: [:])!
    let names: [String]
    switch size {
    case 16: names = ["icon_16x16.png"]
    case 32: names = ["icon_16x16@2x.png", "icon_32x32.png"]
    case 64: names = ["icon_32x32@2x.png"]
    case 128: names = ["icon_128x128.png"]
    case 256: names = ["icon_128x128@2x.png", "icon_256x256.png"]
    case 512: names = ["icon_256x256@2x.png", "icon_512x512.png"]
    default: names = ["icon_512x512@2x.png"]
    }
    for name in names { try data.write(to: URL(fileURLWithPath: output).appendingPathComponent(name)) }
}

// Modern macOS accepts PNG representations directly inside an ICNS container.
// Write it here so packaging doesn't depend on iconutil's system helper service.
func bigEndian(_ value: UInt32) -> Data {
    var number = value.bigEndian
    return withUnsafeBytes(of: &number) { Data($0) }
}
var entries = Data()
for (type, name) in [("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"), ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png"), ("ic11", "icon_16x16@2x.png"), ("ic12", "icon_32x32@2x.png"), ("ic13", "icon_128x128@2x.png"), ("ic14", "icon_256x256@2x.png")] {
    let png = try Data(contentsOf: URL(fileURLWithPath: output).appendingPathComponent(name))
    entries.append(Data(type.utf8)); entries.append(bigEndian(UInt32(png.count + 8))); entries.append(png)
}
var icon = Data("icns".utf8)
icon.append(bigEndian(UInt32(entries.count + 8)))
icon.append(entries)
try icon.write(to: URL(fileURLWithPath: output).deletingLastPathComponent().appendingPathComponent("Luma.icns"))
