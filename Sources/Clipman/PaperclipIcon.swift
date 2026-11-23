import AppKit
import CoreGraphics

/// The Clipman paperclip, drawn in code so the menu bar glyph and the app
/// icon (rendered by scripts/icon) share one source of truth.
enum PaperclipIcon {
    /// Centerline of a classic "Gem" paperclip in a 100×100, y-up space,
    /// standing upright. Stroke it with a round cap to get the wire.
    static func centerline() -> CGMutablePath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: 58, y: 36))                     // inner tail
        p.addLine(to: CGPoint(x: 58, y: 72))
        p.addArc(center: CGPoint(x: 50, y: 72), radius: 8,     // small top loop
                 startAngle: 0, endAngle: .pi, clockwise: false)
        p.addLine(to: CGPoint(x: 42, y: 22))
        p.addArc(center: CGPoint(x: 54, y: 22), radius: 12,    // bottom loop
                 startAngle: .pi, endAngle: 2 * .pi, clockwise: false)
        p.addLine(to: CGPoint(x: 66, y: 78))
        p.addArc(center: CGPoint(x: 52, y: 78), radius: 14,    // big top loop
                 startAngle: 0, endAngle: .pi, clockwise: false)
        p.addLine(to: CGPoint(x: 38, y: 42))                   // outer tail
        return p
    }

    /// The centerline rotated by `angle` and scaled to fit `rect`, plus the
    /// stroke width to use (`wireFraction` is relative to the clip's width).
    static func fitted(in rect: CGRect, angle: CGFloat = -.pi / 5, wireFraction: CGFloat = 0.25)
        -> (path: CGPath, lineWidth: CGFloat)
    {
        let base = centerline()
        let unscaledWire: CGFloat = 28 * wireFraction  // clip is ~28 units wide
        var rotate = CGAffineTransform(translationX: 52, y: 50)
            .rotated(by: angle)
            .translatedBy(x: -52, y: -50)
        guard let rotated = base.copy(using: &rotate) else { return (base, 1) }

        let bounds = rotated.boundingBoxOfPath.insetBy(dx: -unscaledWire / 2, dy: -unscaledWire / 2)
        let scale = min(rect.width / bounds.width, rect.height / bounds.height)
        var fit = CGAffineTransform(translationX: rect.midX, y: rect.midY)
            .scaledBy(x: scale, y: scale)
            .translatedBy(x: -bounds.midX, y: -bounds.midY)
        let fitted = rotated.copy(using: &fit) ?? rotated
        return (fitted, unscaledWire * scale)
    }

    /// Template image for the status bar (auto-tints for light/dark menu bars).
    static func menuBarImage(pointSize: CGFloat = 18) -> NSImage {
        let size = NSSize(width: pointSize, height: pointSize)
        let image = NSImage(size: size, flipped: false) { rect in
            guard let ctx = NSGraphicsContext.current?.cgContext else { return false }
            let (path, width) = fitted(in: rect.insetBy(dx: 1, dy: 1), wireFraction: 0.2)
            ctx.addPath(path)
            ctx.setLineWidth(width)
            ctx.setLineCap(.round)
            ctx.setLineJoin(.round)
            ctx.setStrokeColor(NSColor.black.cgColor)
            ctx.strokePath()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "Clipman"
        return image
    }

    /// Full-color app icon artwork, drawn into a 1024×1024 y-up canvas.
    /// Callers scale the context for smaller sizes.
    static func drawAppIcon(in ctx: CGContext) {
        let canvas = CGRect(x: 0, y: 0, width: 1024, height: 1024)
        let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!
        func color(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor {
            CGColor(colorSpace: sRGB, components: [r / 255, g / 255, b / 255, a])!
        }

        // Squircle-ish tile with the standard macOS icon margins.
        let tile = canvas.insetBy(dx: 100, dy: 100)
        let tilePath = CGPath(roundedRect: tile, cornerWidth: 185, cornerHeight: 185, transform: nil)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -12), blur: 28, color: color(0, 0, 0, 0.35))
        ctx.addPath(tilePath)
        ctx.setFillColor(color(60, 80, 200))
        ctx.fillPath()
        ctx.restoreGState()

        ctx.saveGState()
        ctx.addPath(tilePath)
        ctx.clip()
        let bg = CGGradient(colorsSpace: sRGB,
                            colors: [color(92, 132, 255), color(74, 52, 196)] as CFArray,
                            locations: [0, 1])!
        ctx.drawLinearGradient(bg, start: CGPoint(x: tile.minX, y: tile.maxY),
                               end: CGPoint(x: tile.maxX, y: tile.minY), options: [])

        // A sheet of paper, slightly tilted.
        ctx.saveGState()
        ctx.translateBy(x: 500, y: 470)
        ctx.rotate(by: 0.07)
        let sheet = CGRect(x: -215, y: -270, width: 430, height: 540)
        ctx.setShadow(offset: CGSize(width: 0, height: -10), blur: 24, color: color(20, 10, 80, 0.45))
        ctx.addPath(CGPath(roundedRect: sheet, cornerWidth: 28, cornerHeight: 28, transform: nil))
        ctx.setFillColor(color(250, 250, 255))
        ctx.fillPath()
        ctx.setShadow(offset: .zero, blur: 0, color: nil)
        // Lines of "text".
        ctx.setFillColor(color(198, 204, 228))
        let widths: [CGFloat] = [300, 340, 250, 320, 190]
        for (i, w) in widths.enumerated() {
            let y = sheet.maxY - 170 - CGFloat(i) * 62
            ctx.addPath(CGPath(roundedRect: CGRect(x: sheet.minX + 50, y: y, width: w, height: 26),
                               cornerWidth: 13, cornerHeight: 13, transform: nil))
            ctx.fillPath()
        }
        ctx.restoreGState()

        // The paperclip, gripping the top-right of the sheet.
        let clipRect = CGRect(x: 470, y: 380, width: 400, height: 520)
        let (clip, wire) = fitted(in: clipRect, angle: -.pi / 9, wireFraction: 0.2)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -8), blur: 16, color: color(10, 0, 60, 0.5))
        ctx.addPath(clip)
        ctx.setLineWidth(wire)
        ctx.setStrokeColor(color(120, 128, 150))
        ctx.strokePath()
        ctx.restoreGState()

        // Metallic body: stroke-as-mask filled with a gradient.
        ctx.saveGState()
        ctx.addPath(clip)
        ctx.setLineWidth(wire * 0.82)
        ctx.replacePathWithStrokedPath()
        ctx.clip()
        let metal = CGGradient(colorsSpace: sRGB,
                               colors: [color(250, 251, 255), color(196, 202, 220), color(235, 238, 248)] as CFArray,
                               locations: [0, 0.55, 1])!
        ctx.drawLinearGradient(metal, start: CGPoint(x: clipRect.minX, y: clipRect.maxY),
                               end: CGPoint(x: clipRect.maxX, y: clipRect.minY), options: [])
        ctx.restoreGState()

        // Highlight along the wire.
        ctx.addPath(clip)
        ctx.setLineWidth(wire * 0.18)
        ctx.setStrokeColor(color(255, 255, 255, 0.85))
        ctx.strokePath()

        ctx.restoreGState()
    }
}
