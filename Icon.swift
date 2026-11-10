import AppKit

let destination = CommandLine.arguments[1]
let fm = FileManager.default
try fm.createDirectory(atPath: destination, withIntermediateDirectories: true)
let sizes = [(16,1), (16,2), (32,1), (32,2), (128,1), (128,2), (256,1), (256,2), (512,1), (512,2)]
for (base, scale) in sizes {
    let side = base * scale
    let bitmap = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    let context = NSGraphicsContext(bitmapImageRep: bitmap)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    context.cgContext.scaleBy(x: CGFloat(side) / 1024, y: CGFloat(side) / 1024)
    NSColor(calibratedRed: 0.09, green: 0.11, blue: 0.12, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 60, y: 60, width: 904, height: 904), xRadius: 200, yRadius: 200).fill()
    for (x, y, alpha) in [(246.0, 536.0, 1.0), (536.0, 536.0, 0.68), (246.0, 246.0, 0.68), (536.0, 246.0, 0.24)] {
        NSColor(calibratedRed: 0.65, green: 0.86, blue: 0.73, alpha: alpha).setFill()
        NSBezierPath(roundedRect: NSRect(x: x, y: y, width: 242, height: 242), xRadius: 46, yRadius: 46).fill()
    }
    NSGraphicsContext.restoreGraphicsState()
    let filename = "icon_\(base)x\(base)\(scale == 2 ? "@2x" : "").png"
    try bitmap.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: destination).appendingPathComponent(filename))
}

// Modern ICNS entries carry lossless PNG data; no image conversion service is needed.
func lengthBytes(_ length: Int) -> Data {
    var value = UInt32(length).bigEndian
    return withUnsafeBytes(of: &value) { Data($0) }
}
var entries = Data()
for (type, filename) in [("ic07", "icon_128x128.png"), ("ic08", "icon_256x256.png"),
                         ("ic09", "icon_512x512.png"), ("ic10", "icon_512x512@2x.png")] {
    let png = try Data(contentsOf: URL(fileURLWithPath: destination).appendingPathComponent(filename))
    entries.append(Data(type.utf8))
    entries.append(lengthBytes(png.count + 8))
    entries.append(png)
}
var container = Data("icns".utf8)
container.append(lengthBytes(entries.count + 8))
container.append(entries)
try container.write(to: URL(fileURLWithPath: CommandLine.arguments[2]))
