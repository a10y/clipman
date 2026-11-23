// Renders the app icon (.iconset PNGs) and menu bar previews from PaperclipIcon.swift.
// Usage: make-icon <output.iconset> [preview-dir]
import AppKit
import ImageIO

func writePNG(_ image: CGImage, to url: URL) {
    let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil)!
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { fatalError("failed to write \(url.path)") }
}

func render(pixels: Int, draw: (CGContext) -> Void) -> CGImage {
    let ctx = CGContext(data: nil, width: pixels, height: pixels, bitsPerComponent: 8, bytesPerRow: 0,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.interpolationQuality = .high
    draw(ctx)
    return ctx.makeImage()!
}

let args = CommandLine.arguments
guard args.count >= 2 else {
    print("usage: make-icon <output.iconset> [preview-dir]")
    exit(1)
}
let iconset = URL(fileURLWithPath: args[1])
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)

for base in [16, 32, 128, 256, 512] {
    for scale in [1, 2] {
        let px = base * scale
        let image = render(pixels: px) { ctx in
            ctx.scaleBy(x: CGFloat(px) / 1024, y: CGFloat(px) / 1024)
            PaperclipIcon.drawAppIcon(in: ctx)
        }
        let name = scale == 1 ? "icon_\(base)x\(base).png" : "icon_\(base)x\(base)@2x.png"
        writePNG(image, to: iconset.appendingPathComponent(name))
    }
}

if args.count >= 3 {
    let previews = URL(fileURLWithPath: args[2])
    try FileManager.default.createDirectory(at: previews, withIntermediateDirectories: true)
    for (px, name) in [(18, "menubar.png"), (36, "menubar@2x.png"), (144, "menubar-large.png")] {
        let image = render(pixels: px) { ctx in
            let rect = CGRect(x: 0, y: 0, width: px, height: px)
            ctx.setFillColor(CGColor(gray: 0.92, alpha: 1)); ctx.fill(rect)
            let inset = CGFloat(px) / 18
            let (path, width) = PaperclipIcon.fitted(in: rect.insetBy(dx: inset, dy: inset), wireFraction: 0.2)
            ctx.addPath(path); ctx.setLineWidth(width); ctx.setLineCap(.round); ctx.setLineJoin(.round)
            ctx.setStrokeColor(CGColor(gray: 0.1, alpha: 1)); ctx.strokePath()
        }
        writePNG(image, to: previews.appendingPathComponent(name))
    }
}
