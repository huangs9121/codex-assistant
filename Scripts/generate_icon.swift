import AppKit

guard CommandLine.arguments.count == 2 else {
    fputs("usage: generate_icon.swift OUTPUT.png\n", stderr)
    exit(64)
}

let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
let size = NSSize(width: 1024, height: 1024)

let image = NSImage(size: size, flipped: false, drawingHandler: { rect in
    NSColor(calibratedWhite: 0.10, alpha: 1).setFill()
    NSBezierPath(roundedRect: rect.insetBy(dx: 48, dy: 48), xRadius: 210, yRadius: 210).fill()

    let barRect = NSRect(x: 188, y: 382, width: 648, height: 260)
    NSColor(calibratedWhite: 0.36, alpha: 1).setFill()
    NSBezierPath(roundedRect: barRect, xRadius: 72, yRadius: 72).fill()

    let chargeRect = NSRect(x: 188, y: 382, width: 432, height: 260)
    NSColor.white.setFill()
    NSBezierPath(roundedRect: chargeRect, xRadius: 72, yRadius: 72).fill()

    NSColor(calibratedWhite: 0.70, alpha: 1).setFill()
    NSBezierPath(roundedRect: NSRect(x: 858, y: 450, width: 42, height: 124), xRadius: 18, yRadius: 18).fill()

    return true
})

guard
    let tiff = image.tiffRepresentation,
    let bitmap = NSBitmapImageRep(data: tiff),
    let png = bitmap.representation(using: .png, properties: [:])
else {
    fputs("failed to encode icon PNG\n", stderr)
    exit(1)
}

try png.write(to: outputURL)
