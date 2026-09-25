// Renders the input menu template icon: a filled rounded square with the label knocked out.
// The input menu draws third-party icons into a 16x16pt slot (non-square images get squashed),
// so the box fills the square to match the height of system-drawn badges like ABC.
// Usage: swift scripts/make-icons.swift <out-dir>
import AppKit

let outDir = URL(fileURLWithPath: CommandLine.arguments[1])

let canvas: CGFloat = 16
let cornerRadius: CGFloat = 3.5
let textInset: CGFloat = 1.5

func render(_ label: String, pixels: Int) -> NSBitmapImageRep {
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
        samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
        bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: canvas, height: canvas)
    let context = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context

    NSColor.black.setFill()
    NSBezierPath(roundedRect: NSRect(x: 0, y: 0, width: canvas, height: canvas),
                 xRadius: cornerRadius, yRadius: cornerRadius).fill()

    // Largest bold font that fits inside the inset.
    var fontSize: CGFloat = 12
    var text: NSAttributedString
    repeat {
        text = NSAttributedString(string: label, attributes: [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: NSColor.black,
        ])
        fontSize -= 0.25
    } while text.size().width > canvas - textInset * 2 && fontSize > 4

    // Knock the label out of the filled square.
    context.cgContext.setBlendMode(.destinationOut)
    let size = text.size()
    text.draw(at: NSPoint(x: (canvas - size.width) / 2, y: (canvas - size.height) / 2))

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

for (name, label) in [("kbd", "KBD")] {
    let image = NSImage(size: NSSize(width: canvas, height: canvas))
    image.addRepresentation(render(label, pixels: 16))
    image.addRepresentation(render(label, pixels: 32))
    try! image.tiffRepresentation!.write(to: outDir.appendingPathComponent("\(name).tiff"))
}
