import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// All layout coordinates are top-down in a 1500 × 1000 design space.
let args = CommandLine.arguments
guard args.count == 6, let swatchY = Int(args[5]) else {
    fatalError("Usage: cards iPhone-directory caption-atlas.png app-icon.png output-directory swatch-center-y")
}
let captures = URL(fileURLWithPath: args[1])
let destination = URL(fileURLWithPath: args[4])
let space = CGColorSpace(name: CGColorSpace.sRGB)!

func load(_ url: URL) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else { fatalError("Cannot read " + url.path) }
    return image
}

func rect(_ x: CGFloat, _ y: CGFloat, _ width: CGFloat, _ height: CGFloat) -> CGRect {
    CGRect(x: x, y: 1000 - y - height, width: width, height: height)
}

func color(_ red: CGFloat, _ green: CGFloat, _ blue: CGFloat, _ alpha: CGFloat = 1) -> CGColor {
    CGColor(colorSpace: space, components: [red, green, blue, alpha])!
}

let atlas = load(URL(fileURLWithPath: args[2]))
let icon = load(URL(fileURLWithPath: args[3]))
let window = rect(696, 326, 448, 348)
let windowPath = CGPath(roundedRect: window, cornerWidth: 17, cornerHeight: 17, transform: nil)
let logo = rect(369, 389, 52, 52)
let logoPath = CGPath(roundedRect: logo, cornerWidth: 11.5, cornerHeight: 11.5, transform: nil)
let gradient = CGGradient(colorsSpace: space,
    colors: [color(0.970, 0.964, 0.950), color(0.958, 0.958, 0.947), color(0.890, 0.911, 0.930)] as CFArray,
    locations: [0, 0.43, 1])!

let signature = NSMutableAttributedString(string: "Moro for Mastodon", attributes: [
    .font: NSFont.systemFont(ofSize: 25, weight: .regular), .kern: -0.42,
    .foregroundColor: NSColor(srgbRed: 0.265, green: 0.308, blue: 0.353, alpha: 1)
])
signature.addAttributes([.font: NSFont.systemFont(ofSize: 26, weight: .semibold),
                         .foregroundColor: NSColor(srgbRed: 0.113, green: 0.149, blue: 0.191, alpha: 1)],
                        range: NSRange(location: 0, length: 4))
let wordmark = CTLineCreateWithAttributedString(signature)
let shots = [("home-light.png", 311), ("inbox.png", 183), ("profile.png", 289), ("display.png", swatchY - 693)]

for (index, shot) in shots.enumerated() {
    autoreleasepool {
        let ctx = CGContext(data: nil, width: 3840, height: 2560, bitsPerComponent: 8,
                            bytesPerRow: 3840 * 4, space: space,
                            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        ctx.scaleBy(x: 2.56, y: 2.56)
        ctx.interpolationQuality = .high
        ctx.setShouldSmoothFonts(false)
        ctx.drawLinearGradient(gradient, start: CGPoint(x: 265, y: 685), end: CGPoint(x: 1295, y: 400),
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])

        ctx.saveGState()
        ctx.setShadow(offset: CGSize(width: 0, height: -5), blur: 16, color: color(0.15, 0.19, 0.22, 0.16))
        ctx.setFillColor(color(1, 1, 1))
        ctx.addPath(windowPath)
        ctx.fillPath()
        ctx.restoreGState()

        let native = load(captures.appendingPathComponent(shot.0))
        precondition(native.width == 1320 && native.height == 2868, "Unexpected iPhone capture dimensions")
        let inset = index == 3 ? 30 : 0
        let cropWidth = CGFloat(native.width - 2 * inset)
        let cropSize = CGSize(width: cropWidth, height: round(cropWidth * window.height / window.width))
        let sourceRect = CGRect(origin: CGPoint(x: inset, y: shot.1), size: cropSize)
        ctx.saveGState()
        ctx.addPath(windowPath)
        ctx.clip()
        ctx.draw(native.cropping(to: sourceRect)!, in: window)
        ctx.restoreGState()
        ctx.setLineWidth(0.65)
        ctx.setStrokeColor(color(0.36, 0.41, 0.46, 0.22))
        ctx.addPath(windowPath)
        ctx.strokePath()

        ctx.saveGState()
        ctx.addPath(logoPath)
        ctx.clip()
        ctx.draw(icon, in: logo)
        ctx.restoreGState()

        let cellW = atlas.width / 2, cellH = atlas.height / 2
        let cell = CGRect(x: index % 2 * cellW, y: index / 2 * cellH, width: cellW, height: cellH)
        ctx.draw(atlas.cropping(to: cell)!, in: rect(364, 379, 310, 200))
        ctx.textPosition = CGPoint(x: 369 - CTLineGetBoundsWithOptions(wordmark, .useGlyphPathBounds).minX, y: 1000 - 657)
        CTLineDraw(wordmark, ctx)

        let url = destination.appendingPathComponent("page-\(index).png")
        let output = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(output, ctx.makeImage()!, nil)
        precondition(CGImageDestinationFinalize(output), "Cannot write " + url.path)
    }
}
