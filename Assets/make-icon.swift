// Turns the square logo into a macOS app icon set:
//   swift Assets/make-icon.swift Assets/popoli.png build/AppIcon.iconset
// The artwork is placed on the standard macOS icon grid (an 824 pt rounded square with
// continuous corners inside a 1024 pt canvas, with a soft shadow), so it sits in line with
// other icons instead of being shown as a raw square.
import AppKit
import SwiftUI

let arguments = CommandLine.arguments
guard arguments.count == 3, let logo = NSImage(contentsOfFile: arguments[1]) else {
    print("usage: make-icon.swift <logo.png> <output.iconset>")
    exit(1)
}
let output = URL(fileURLWithPath: arguments[2])
try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

func render(pixels: Int) -> Data {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                               samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                               bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let context = NSGraphicsContext.current!.cgContext
    context.interpolationQuality = .high

    let scale = CGFloat(pixels) / 1024
    let rect = CGRect(x: 100 * scale, y: 100 * scale, width: 824 * scale, height: 824 * scale)
    let shape = RoundedRectangle(cornerRadius: 185.4 * scale, style: .continuous).path(in: rect).cgPath

    context.saveGState()
    context.setShadow(offset: CGSize(width: 0, height: -10 * scale), blur: 24 * scale,
                      color: NSColor.black.withAlphaComponent(0.3).cgColor)
    context.addPath(shape)
    context.setFillColor(NSColor.white.cgColor)
    context.fillPath()
    context.restoreGState()

    context.addPath(shape)
    context.clip()
    logo.draw(in: rect)

    NSGraphicsContext.restoreGraphicsState()
    return rep.representation(using: .png, properties: [:])!
}

let sizes: [(Int, String)] = [
    (16, "16x16"), (32, "16x16@2x"), (32, "32x32"), (64, "32x32@2x"), (128, "128x128"),
    (256, "128x128@2x"), (256, "256x256"), (512, "256x256@2x"), (512, "512x512"), (1024, "512x512@2x"),
]
for (pixels, name) in sizes {
    try render(pixels: pixels).write(to: output.appendingPathComponent("icon_\(name).png"))
}
