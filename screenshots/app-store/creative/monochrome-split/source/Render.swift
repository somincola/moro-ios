import AppKit
import CoreGraphics
import CoreText
import Foundation

// MARK: - Math & Easing

@inline(__always) func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
    min(max(x, lo), hi)
}

@inline(__always) func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double {
    a + (b - a) * t
}

@inline(__always) func smoothstep(_ t: Double) -> Double {
    let u = clamp(t, 0.0, 1.0)
    return u * u * (3.0 - 2.0 * u)
}

@inline(__always) func easeOutCubic(_ t: Double) -> Double {
    let u = clamp(t, 0.0, 1.0)
    let inv = 1.0 - u
    return 1.0 - inv * inv * inv
}

@inline(__always) func easeInOutQuint(_ t: Double) -> Double {
    let u = clamp(t, 0.0, 1.0)
    if u < 0.5 {
        return 16.0 * u * u * u * u * u
    } else {
        let f = -2.0 * u + 2.0
        return 1.0 - (f * f * f * f * f) * 0.5
    }
}

/// Crisp Apple-style spring settle with subtle 1.6% overshoot, hitting 0 at t=0 and 1 at t=1.
@inline(__always) func springSettle(_ t: Double) -> Double {
    let u = clamp(t, 0.0, 1.0)
    if u <= 0.0 { return 0.0 }
    if u >= 1.0 { return 1.0 }
    let base = 1.0 - pow(1.0 - u, 3.2)
    let overshoot = sin(u * Double.pi) * exp(-u * 3.6) * 0.055 * smoothstep(u * 3.0)
    return base + overshoot * (1.0 - u)
}

// MARK: - Models

struct BeatCopy: Decodable {
    let kicker: String
    let lines: [String]
    let subtitle: String
}

struct LocaleCopy: Decodable {
    let rtl: Bool
    let brand: String
    let beats: [BeatCopy]
}

struct SplitScreen {
    let full: CGImage
    let statusBar: CGImage
    let headerBar: CGImage? // non-nil for Home screens -> smoothly collapses on scroll!
    let chrome: CGImage
    let body: CGImage
    let srcWidth: CGFloat
    let srcHeight: CGFloat
    let statusSrcH: CGFloat
    let chromeSrcH: CGFloat
}

// MARK: - CoreGraphics Utilities

let srgbSpace = CGColorSpace(name: CGColorSpace.sRGB)!

func rgba(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1.0) -> CGColor {
    CGColor(colorSpace: srgbSpace, components: [r / 255.0, g / 255.0, b / 255.0, a])!
}

func loadCGImage(_ path: String) -> CGImage {
    let url = URL(fileURLWithPath: path)
    guard let src = CGImageSourceCreateWithURL(url as CFURL, nil),
          let img = CGImageSourceCreateImageAtIndex(src, 0, nil) else {
        fputs("ERROR: Failed to load image at \(path)\n", stderr)
        exit(1)
    }
    return img
}

func loadSplitScreen(_ path: String, chromeSrcH: Int = 344, collapsibleHeader: Bool = false, statusSrcH: Int = 176) -> SplitScreen {
    let img = loadCGImage(path)
    let w = img.width
    let h = img.height
    let ch = min(chromeSrcH, h / 4)
    let st = min(statusSrcH, ch)
    let statusBar = img.cropping(to: CGRect(x: 0, y: 0, width: w, height: st))!
    let headerBar: CGImage? = collapsibleHeader && ch > st
        ? img.cropping(to: CGRect(x: 0, y: st, width: w, height: ch - st))
        : nil
    let chrome = img.cropping(to: CGRect(x: 0, y: 0, width: w, height: ch))!
    let body = img.cropping(to: CGRect(x: 0, y: ch, width: w, height: h - ch))!
    return SplitScreen(
        full: img,
        statusBar: statusBar,
        headerBar: headerBar,
        chrome: chrome,
        body: body,
        srcWidth: CGFloat(w),
        srcHeight: CGFloat(h),
        statusSrcH: CGFloat(st),
        chromeSrcH: CGFloat(ch)
    )
}

func makeTopDownContext(width: Int, height: Int, data: UnsafeMutableRawPointer? = nil) -> CGContext {
    let bitmapInfo = CGBitmapInfo.byteOrder32Little.rawValue | CGImageAlphaInfo.premultipliedFirst.rawValue
    guard let ctx = CGContext(
        data: data,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: width * 4,
        space: srgbSpace,
        bitmapInfo: bitmapInfo
    ) else {
        fputs("ERROR: Failed to allocate CGContext \(width)x\(height)\n", stderr)
        exit(1)
    }
    ctx.interpolationQuality = .high
    ctx.setAllowsAntialiasing(true)
    ctx.setShouldAntialias(true)
    // Flip to top-down coordinate space: (0,0) top-left, +Y down
    ctx.translateBy(x: 0, y: CGFloat(height))
    ctx.scaleBy(x: 1, y: -1)
    return ctx
}

@inline(__always)
func drawImageTopDown(_ ctx: CGContext, _ img: CGImage, in rect: CGRect) {
    ctx.saveGState()
    ctx.translateBy(x: rect.minX, y: rect.maxY)
    ctx.scaleBy(x: 1, y: -1)
    ctx.draw(img, in: CGRect(x: 0, y: 0, width: rect.width, height: rect.height))
    ctx.restoreGState()
}

func roundedRectPath(_ rect: CGRect, radius: CGFloat) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
}

func savePNG(_ image: CGImage, to path: String) {
    let url = URL(fileURLWithPath: path)
    try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    guard let dest = CGImageDestinationCreateWithURL(url as CFURL, "public.png" as CFString, 1, nil) else {
        fputs("ERROR: Failed to create PNG destination \(path)\n", stderr)
        exit(1)
    }
    CGImageDestinationAddImage(dest, image, nil)
    if !CGImageDestinationFinalize(dest) {
        fputs("ERROR: Failed to write PNG \(path)\n", stderr)
        exit(1)
    }
}

func writeAll(_ fd: Int32, _ ptr: UnsafeRawPointer, _ count: Int) {
    var written = 0
    while written < count {
        let n = Darwin.write(fd, ptr.advanced(by: written), count - written)
        if n <= 0 {
            if errno == EINTR { continue }
            fputs("ERROR: stdout write failed (errno \(errno))\n", stderr)
            exit(1)
        }
        written += n
    }
}

// MARK: - Typography

func localizedFont(locale: String, size: CGFloat, weight: NSFont.Weight) -> NSFont {
    let candidates: [String]
    switch locale {
    case "zh-Hans":
        candidates = weight >= .semibold
            ? ["PingFangSC-Semibold", "PingFangSC-Medium"]
            : ["PingFangSC-Regular", "PingFangSC-Light"]
    case "zh-Hant":
        candidates = weight >= .semibold
            ? ["PingFangTC-Semibold", "PingFangTC-Medium"]
            : ["PingFangTC-Regular", "PingFangTC-Light"]
    case "ja":
        candidates = weight >= .semibold
            ? ["HiraginoSans-W6", "HiraginoSans-W7"]
            : ["HiraginoSans-W4", "HiraginoSans-W3"]
    case "ar-SA":
        candidates = weight >= .semibold
            ? ["GeezaPro-Bold", "SFArabic-Bold"]
            : ["GeezaPro", "SFArabic-Regular"]
    default:
        return NSFont.systemFont(ofSize: size, weight: weight)
    }
    for name in candidates {
        if let f = NSFont(name: name, size: size) {
            return f
        }
    }
    return NSFont.systemFont(ofSize: size, weight: weight)
}

func isCJK(_ locale: String) -> Bool {
    locale == "zh-Hans" || locale == "zh-Hant" || locale == "ja"
}

func drawAttributedText(
    in ctx: CGContext,
    string: String,
    font: NSFont,
    color: NSColor,
    rect: CGRect,
    alignment: NSTextAlignment,
    rtl: Bool,
    kern: CGFloat = 0.0,
    lineHeightMultiple: CGFloat = 1.25
) {
    let para = NSMutableParagraphStyle()
    para.alignment = alignment
    para.lineBreakMode = .byWordWrapping
    para.lineHeightMultiple = lineHeightMultiple
    para.baseWritingDirection = rtl ? .rightToLeft : .leftToRight

    var attrs: [NSAttributedString.Key: Any] = [
        .font: font,
        .foregroundColor: color,
        .paragraphStyle: para
    ]
    if !rtl && abs(kern) > 0.01 {
        attrs[.kern] = kern
    }
    let attrStr = NSAttributedString(string: string, attributes: attrs)

    NSGraphicsContext.saveGraphicsState()
    let nsCtx = NSGraphicsContext(cgContext: ctx, flipped: true)
    NSGraphicsContext.current = nsCtx
    attrStr.draw(with: rect, options: [.usesLineFragmentOrigin, .usesFontLeading])
    NSGraphicsContext.restoreGraphicsState()
}

func measureSingleLine(string: String, font: NSFont, rtl: Bool, kern: CGFloat) -> CGSize {
    var attrs: [NSAttributedString.Key: Any] = [.font: font]
    if !rtl && abs(kern) > 0.01 {
        attrs[.kern] = kern
    }
    return (string as NSString).size(withAttributes: attrs)
}

// MARK: - Studio Titanium iPhone Renderer (Pre-baked Shadow + Crisp Hardware Frame)

struct PhoneGeometry {
    let outerW: CGFloat
    let outerH: CGFloat
    let chassisPad: CGFloat
    let screenW: CGFloat
    let screenH: CGFloat
    let outerRadius: CGFloat
    let screenRadius: CGFloat
    let shadowImg: CGImage
    let shadowPadX: CGFloat
    let shadowPadTop: CGFloat
    let shadowPadBottom: CGFloat

    init(outerW: CGFloat) {
        self.outerW = outerW
        self.chassisPad = outerW * 0.036
        self.screenW = outerW - 2.0 * chassisPad
        self.screenH = screenW * (2868.0 / 1320.0)
        self.outerH = screenH + 2.0 * chassisPad
        self.outerRadius = outerW * 0.148
        self.screenRadius = max(12.0, outerRadius - chassisPad * 0.92)

        // Pre-bake lush multi-layer studio shadow at 0.5x resolution (blazing fast & silky smooth!)
        self.shadowPadX = 240.0
        self.shadowPadTop = 180.0
        self.shadowPadBottom = 300.0
        let scale: CGFloat = 0.5
        let sw = Int(ceil((outerW + shadowPadX * 2.0) * scale))
        let sh = Int(ceil((outerH + shadowPadTop + shadowPadBottom) * scale))
        let sctx = makeTopDownContext(width: sw, height: sh)
        sctx.scaleBy(x: scale, y: scale)
        let phoneRect = CGRect(x: shadowPadX, y: shadowPadTop, width: outerW, height: outerH)
        let path = roundedRectPath(phoneRect, radius: outerRadius)

        // Layer 1: wide gallery ambient drop shadow
        sctx.saveGState()
        sctx.setShadow(offset: CGSize(width: 0, height: -52 * scale), blur: 130 * scale, color: rgba(8, 10, 14, 0.24))
        sctx.addPath(path)
        sctx.setFillColor(rgba(0, 0, 0, 1.0))
        sctx.fillPath()
        sctx.restoreGState()

        // Layer 2: tighter sculpted contact shadow
        sctx.saveGState()
        sctx.setShadow(offset: CGSize(width: 0, height: -18 * scale), blur: 42 * scale, color: rgba(8, 10, 14, 0.28))
        sctx.addPath(path)
        sctx.setFillColor(rgba(0, 0, 0, 1.0))
        sctx.fillPath()
        sctx.restoreGState()

        self.shadowImg = sctx.makeImage()!
    }
}

func drawStudioPhone(
    in ctx: CGContext,
    geom: PhoneGeometry,
    centerX: CGFloat,
    topY: CGFloat,
    scale: CGFloat = 1.0,
    rotationDeg: CGFloat = 0.0,
    opacity: CGFloat = 1.0,
    screenA: SplitScreen,
    scrollA: CGFloat = 0.0,
    screenB: SplitScreen? = nil,
    scrollB: CGFloat = 0.0,
    crossfadeB: CGFloat = 0.0,
    slideBOffset: CGFloat = 0.0,
    sheenPhase: CGFloat = 0.0,
    shadowStrength: CGFloat = 1.0
) {
    ctx.saveGState()
    // Anchor rotation/scale around the phone's visual upper-middle center
    let pivotY = topY + geom.outerH * 0.34
    ctx.translateBy(x: centerX, y: pivotY)
    if abs(rotationDeg) > 0.001 {
        ctx.rotate(by: rotationDeg * .pi / 180.0)
    }
    if abs(scale - 1.0) > 0.0005 {
        ctx.scaleBy(x: scale, y: scale)
    }
    ctx.translateBy(x: -geom.outerW * 0.5, y: -(pivotY - topY))

    if opacity < 0.999 {
        ctx.setAlpha(opacity)
    }

    // 1. Pre-baked multi-layer studio shadow
    if shadowStrength > 0.01 {
        ctx.saveGState()
        ctx.setAlpha(opacity * shadowStrength)
        let sRect = CGRect(
            x: -geom.shadowPadX,
            y: -geom.shadowPadTop,
            width: geom.outerW + geom.shadowPadX * 2.0,
            height: geom.outerH + geom.shadowPadTop + geom.shadowPadBottom
        )
        drawImageTopDown(ctx, geom.shadowImg, in: sRect)
        ctx.restoreGState()
    }

    let outerRect = CGRect(x: 0, y: 0, width: geom.outerW, height: geom.outerH)
    let outerPath = roundedRectPath(outerRect, radius: geom.outerRadius)

    // 2. Precision Titanium Hardware Side Buttons
    let btnW: CGFloat = geom.outerW * 0.0065
    ctx.setFillColor(rgba(48, 52, 60, 0.95))
    // Left edge: Action + Vol Up + Vol Down
    let leftButtons: [(CGFloat, CGFloat)] = [(0.135, 0.032), (0.195, 0.068), (0.280, 0.068)]
    for (yFrac, hFrac) in leftButtons {
        let r = CGRect(x: -btnW + 1.5, y: geom.outerH * yFrac, width: btnW, height: geom.outerH * hFrac)
        ctx.addPath(roundedRectPath(r, radius: btnW * 0.45))
        ctx.fillPath()
    }
    // Right edge: Power button
    let pwr = CGRect(x: geom.outerW - 1.5, y: geom.outerH * 0.225, width: btnW, height: geom.outerH * 0.105)
    ctx.addPath(roundedRectPath(pwr, radius: btnW * 0.45))
    ctx.fillPath()

    // 3. Outer Brushed Titanium Chassis Shell
    ctx.saveGState()
    ctx.addPath(outerPath)
    ctx.clip()
    let titaniumGrad = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(52, 56, 65), rgba(18, 20, 24), rgba(34, 37, 44), rgba(14, 16, 20)] as CFArray,
        locations: [0.0, 0.35, 0.72, 1.0]
    )!
    ctx.drawLinearGradient(
        titaniumGrad,
        start: CGPoint(x: 0, y: 0),
        end: CGPoint(x: geom.outerW, y: geom.outerH * 0.6),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    ctx.restoreGState()

    // 4. Inner Pure OLED Black Bezel
    let bezelInset = geom.outerW * 0.0085
    let bezelRect = outerRect.insetBy(dx: bezelInset, dy: bezelInset)
    let bezelPath = roundedRectPath(bezelRect, radius: geom.outerRadius - bezelInset * 0.9)
    ctx.addPath(bezelPath)
    ctx.setFillColor(rgba(5, 6, 8, 1.0))
    ctx.fillPath()

    // 5. Screen Content (Split-layer scrolling + smooth beat crossfade!)
    let screenRect = CGRect(x: geom.chassisPad, y: geom.chassisPad, width: geom.screenW, height: geom.screenH)
    let screenPath = roundedRectPath(screenRect, radius: geom.screenRadius)

    ctx.saveGState()
    ctx.addPath(screenPath)
    ctx.clip()

    // Base black screen fill
    ctx.setFillColor(rgba(10, 11, 14, 1.0))
    ctx.fill(screenRect)

    func drawSplit(_ s: SplitScreen, scrollPx: CGFloat, alpha: CGFloat, extraY: CGFloat) {
        guard alpha > 0.002 else { return }
        ctx.saveGState()
        if alpha < 0.999 { ctx.setAlpha(alpha * opacity) }
        let pxScale = geom.screenW / s.srcWidth
        let chromeH = s.chromeSrcH * pxScale
        let bodyH = (s.srcHeight - s.chromeSrcH) * pxScale
        let scrollDraw = scrollPx * pxScale

        if let headerBar = s.headerBar {
            // Authentic Moro iOS scroll-driven header collapse:
            // Floating Home header glides up and fades behind the pinned 9:41 status bar as feed scrolls!
            let statusH = s.statusSrcH * pxScale
            let headerH = chromeH - statusH
            let collapseP = CGFloat(smoothstep(Double(scrollPx) / 145.0))

            let bodyRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + chromeH - scrollDraw + extraY,
                width: geom.screenW,
                height: bodyH
            )
            drawImageTopDown(ctx, s.body, in: bodyRect)

            if collapseP < 0.995 {
                ctx.saveGState()
                ctx.setAlpha(alpha * opacity * (1.0 - collapseP))
                let headerRect = CGRect(
                    x: screenRect.minX,
                    y: screenRect.minY + statusH - collapseP * headerH * 0.92 + extraY,
                    width: geom.screenW,
                    height: headerH
                )
                drawImageTopDown(ctx, headerBar, in: headerRect)
                ctx.restoreGState()
            }

            let statusRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + extraY,
                width: geom.screenW,
                height: statusH
            )
            drawImageTopDown(ctx, s.statusBar, in: statusRect)
        } else {
            let bodyRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + chromeH - scrollDraw + extraY,
                width: geom.screenW,
                height: bodyH
            )
            drawImageTopDown(ctx, s.body, in: bodyRect)

            let chromeRect = CGRect(
                x: screenRect.minX,
                y: screenRect.minY + extraY,
                width: geom.screenW,
                height: chromeH
            )
            drawImageTopDown(ctx, s.chrome, in: chromeRect)
            if scrollPx > 2.0 {
                let edgeAlpha = CGFloat(min(1.0, scrollPx / 32.0)) * 0.14
                ctx.setFillColor(rgba(128, 134, 146, edgeAlpha))
                ctx.fill(CGRect(x: screenRect.minX, y: screenRect.minY + chromeH + extraY - 1.0, width: geom.screenW, height: 1.5))
            }
        }
        ctx.restoreGState()
    }

    if let sb = screenB, crossfadeB > 0.001 {
        let aAlpha = 1.0 - crossfadeB
        drawSplit(screenA, scrollPx: scrollA, alpha: aAlpha, extraY: -slideBOffset * crossfadeB * 0.35)
        drawSplit(sb, scrollPx: scrollB, alpha: crossfadeB, extraY: slideBOffset * (1.0 - crossfadeB))
    } else {
        drawSplit(screenA, scrollPx: scrollA, alpha: 1.0, extraY: 0.0)
    }

    // Authentic Dynamic Island pill (centered in status bar slot)
    let diW = geom.screenW * 0.286
    let diH = geom.screenW * 0.084
    let diRect = CGRect(
        x: screenRect.midX - diW * 0.5,
        y: screenRect.minY + geom.screenW * 0.025,
        width: diW,
        height: diH
    )
    ctx.addPath(roundedRectPath(diRect, radius: diH * 0.5))
    ctx.setFillColor(rgba(5, 6, 8, 1.0))
    ctx.fillPath()

    // Subtle dark sapphire camera lens inside right end of Dynamic Island
    let lensD = diH * 0.42
    let lensRect = CGRect(
        x: diRect.maxX - diH * 0.72,
        y: diRect.midY - lensD * 0.5,
        width: lensD,
        height: lensD
    )
    ctx.setFillColor(rgba(22, 28, 42, 0.9))
    ctx.fillEllipse(in: lensRect)
    ctx.setFillColor(rgba(110, 145, 255, 0.24))
    ctx.fillEllipse(in: lensRect.insetBy(dx: lensD * 0.26, dy: lensD * 0.26))

    // Ultra-subtle studio glass reflection band across screen
    let bandX = lerp(-geom.screenW * 0.45, geom.screenW * 1.45, Double(sheenPhase))
    ctx.saveGState()
    ctx.translateBy(x: screenRect.minX + CGFloat(bandX), y: screenRect.minY)
    ctx.rotate(by: -0.26)
    let sheenGrad = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(255, 255, 255, 0.0), rgba(255, 255, 255, 0.032), rgba(255, 255, 255, 0.0)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.drawLinearGradient(
        sheenGrad,
        start: CGPoint(x: -240, y: 0),
        end: CGPoint(x: 240, y: 0),
        options: []
    )
    ctx.restoreGState()

    // Crisp hairline inner screen edge highlight
    ctx.addPath(screenPath)
    ctx.setStrokeColor(rgba(255, 255, 255, 0.11))
    ctx.setLineWidth(1.5)
    ctx.strokePath()
    ctx.restoreGState()

    // 6. Outer Titanium Rim Specular Stroke
    ctx.addPath(roundedRectPath(outerRect.insetBy(dx: 1.5, dy: 1.5), radius: geom.outerRadius - 1.5))
    ctx.setStrokeColor(rgba(130, 138, 154, 0.42))
    ctx.setLineWidth(2.6)
    ctx.strokePath()

    ctx.restoreGState()
}

// MARK: - Split Monochrome Stage Background Builder

func buildSplitBackground(
    width: Int,
    height: Int,
    splitX: CGFloat,
    rtl: Bool,
    watermark: CGImage,
    topScrimAlpha: CGFloat
) -> CGImage {
    let ctx = makeTopDownContext(width: width, height: height)
    let W = CGFloat(width)
    let H = CGFloat(height)

    let darkRect = rtl
        ? CGRect(x: splitX, y: 0, width: W - splitX, height: H)
        : CGRect(x: 0, y: 0, width: splitX, height: H)
    let lightRect = rtl
        ? CGRect(x: 0, y: 0, width: splitX, height: H)
        : CGRect(x: splitX, y: 0, width: W - splitX, height: H)

    // 1. Matte Obsidian Monolith (39%)
    ctx.saveGState()
    ctx.clip(to: darkRect)
    let darkGrad = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(8, 9, 12), rgba(15, 17, 22), rgba(10, 11, 15)] as CFArray,
        locations: [0.0, 0.48, 1.0]
    )!
    ctx.drawLinearGradient(
        darkGrad,
        start: CGPoint(x: darkRect.minX, y: 0),
        end: CGPoint(x: darkRect.maxX, y: H),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Subtle soft radial depth pool behind brand/headline
    let darkGlow = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(255, 255, 255, 0.042), rgba(255, 255, 255, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    let glowCenter = CGPoint(x: darkRect.midX, y: H * 0.44)
    ctx.drawRadialGradient(
        darkGlow,
        startCenter: glowCenter,
        startRadius: 0,
        endCenter: glowCenter,
        endRadius: darkRect.width * 0.88,
        options: []
    )

    // Giant cropped architectural monochrome elephant watermark
    ctx.saveGState()
    ctx.setAlpha(0.032)
    let wmSize: CGFloat = H > 2000 ? 1080.0 : 880.0
    let wmX: CGFloat = rtl ? (W - wmSize + 210.0) : (-210.0)
    let wmY: CGFloat = H - wmSize * 0.72
    drawImageTopDown(ctx, watermark, in: CGRect(x: wmX, y: wmY, width: wmSize, height: wmSize))
    ctx.restoreGState()
    ctx.restoreGState()

    // 2. Architectural Stone-White Stage (61%)
    ctx.saveGState()
    ctx.clip(to: lightRect)
    let lightGrad = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(242, 244, 247), rgba(232, 235, 240), rgba(224, 228, 234)] as CFArray,
        locations: [0.0, 0.52, 1.0]
    )!
    ctx.drawLinearGradient(
        lightGrad,
        start: CGPoint(x: lightRect.minX, y: 0),
        end: CGPoint(x: lightRect.maxX, y: H),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )

    // Sculpted gallery spotlight behind hero phone
    let spot = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(255, 255, 255, 0.62), rgba(255, 255, 255, 0.0)] as CFArray,
        locations: [0.0, 1.0]
    )!
    let spotCenter = CGPoint(
        x: rtl ? lightRect.minX + lightRect.width * 0.56 : lightRect.minX + lightRect.width * 0.42,
        y: H * 0.48
    )
    ctx.drawRadialGradient(
        spot,
        startCenter: spotCenter,
        startRadius: 0,
        endCenter: spotCenter,
        endRadius: lightRect.width * 0.62,
        options: []
    )

    // Tasteful top scrim (keeps iOS 26 status bar & Liquid Glass buttons crisp without muddiness)
    if topScrimAlpha > 0.001 {
        let scrim = CGGradient(
            colorsSpace: srgbSpace,
            colors: [rgba(14, 16, 22, topScrimAlpha), rgba(14, 16, 22, 0.0)] as CFArray,
            locations: [0.0, 1.0]
        )!
        ctx.drawLinearGradient(
            scrim,
            start: CGPoint(x: lightRect.midX, y: 0),
            end: CGPoint(x: lightRect.midX, y: 280.0),
            options: []
        )
    }
    ctx.restoreGState()

    // 3. Machined Architectural Seam along 39%/61% split
    ctx.setFillColor(rgba(255, 255, 255, 0.09))
    ctx.fill(CGRect(x: rtl ? splitX : splitX - 2.0, y: 0, width: 2.0, height: H))
    ctx.setFillColor(rgba(0, 0, 0, 0.08))
    ctx.fill(CGRect(x: rtl ? splitX - 2.0 : splitX, y: 0, width: 2.0, height: H))

    return ctx.makeImage()!
}

/// Subtle moving diagonal gallery sheen across the obsidian monolith (seamless periodic phase 0..1)
func drawObsidianSheen(in ctx: CGContext, darkRect: CGRect, phase: Double) {
    ctx.saveGState()
    ctx.clip(to: darkRect)
    let sweep = sin(phase * 2.0 * Double.pi) // -1..+1 seamless periodic!
    let centerX = darkRect.midX + CGFloat(sweep) * darkRect.width * 0.58
    ctx.translateBy(x: centerX, y: darkRect.midY)
    ctx.rotate(by: -0.34)
    let grad = CGGradient(
        colorsSpace: srgbSpace,
        colors: [rgba(255, 255, 255, 0.0), rgba(255, 255, 255, 0.036), rgba(255, 255, 255, 0.0)] as CFArray,
        locations: [0.0, 0.5, 1.0]
    )!
    ctx.drawLinearGradient(
        grad,
        start: CGPoint(x: -380, y: 0),
        end: CGPoint(x: 380, y: 0),
        options: []
    )
    ctx.restoreGState()
}

// MARK: - Header Film Renderer (3840 × 1646, 15.0s, 30 fps = 450 frames)

final class HeaderRenderer {
    let W = 3840
    let H = 1646
    let FPS = 30.0
    let totalFrames = 450
    let splitX: CGFloat = 1498.0

    let baseBG: CGImage
    let brandMark: CGImage
    let homeLight: SplitScreen
    let homeDark: SplitScreen
    let heroGeom: PhoneGeometry
    let wordmarkImg: CGImage

    init(assetsDir: String, screenshotsDir: String) {
        let wm = loadCGImage("\(assetsDir)/moro-mark-white.png")
        self.brandMark = loadCGImage("\(assetsDir)/moro-mark-transparent.png")
        self.homeLight = loadSplitScreen("\(screenshotsDir)/home-light.png", chromeSrcH: 334, collapsibleHeader: true, statusSrcH: 176)
        self.homeDark = loadSplitScreen("\(screenshotsDir)/home-dark.png", chromeSrcH: 334, collapsibleHeader: true, statusSrcH: 176)
        self.baseBG = buildSplitBackground(
            width: W,
            height: H,
            splitX: splitX,
            rtl: false,
            watermark: wm,
            topScrimAlpha: 0.09
        )
        self.heroGeom = PhoneGeometry(outerW: 1050.0)

        // Pre-render crisp "Moro" wordmark once
        let wctx = makeTopDownContext(width: 520, height: 150)
        drawAttributedText(
            in: wctx,
            string: "Moro",
            font: NSFont.systemFont(ofSize: 106, weight: .semibold),
            color: NSColor(white: 1.0, alpha: 0.94),
            rect: CGRect(x: 0, y: 10, width: 520, height: 130),
            alignment: .center,
            rtl: false,
            kern: -2.4,
            lineHeightMultiple: 1.0
        )
        self.wordmarkImg = wctx.makeImage()!
    }

    func renderFrame(_ frameIndex: Int, into ctx: CGContext) {
        let t = Double(frameIndex) / FPS // 0.0 .. 14.967s
        let loopPhase = t / 15.0

        // 1. Static split base + subtle periodic obsidian sheen
        drawImageTopDown(ctx, baseBG, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))
        drawObsidianSheen(in: ctx, darkRect: CGRect(x: 0, y: 0, width: splitX, height: CGFloat(H)), phase: loopPhase)

        // 2. Left Obsidian Brand Hero (centered at x=1085 for BOTH iPhone crop & 21:9 elegance!)
        // Beat-synced subtle downbeat pulse at t = 0, 6.0, 12.0
        func beatPulse(at beatT: Double) -> Double {
            var dt = t - beatT
            if dt < -7.5 { dt += 15.0 }
            if dt > 7.5 { dt -= 15.0 }
            if dt < 0 || dt > 0.75 { return 0.0 }
            return sin((dt / 0.75) * Double.pi) * exp(-dt * 4.5)
        }
        let pulse = beatPulse(at: 0.0) + beatPulse(at: 6.0) + beatPulse(at: 12.0)
        let breathY = sin(t * 2.0 * Double.pi / 3.0) * 6.0 // exact 80 BPM bar breathing!
        let markCenterX: CGFloat = 1085.0
        let markCenterY: CGFloat = 755.0 + CGFloat(breathY)
        let markScale: CGFloat = 1.0 + CGFloat(pulse) * 0.022
        let markSize: CGFloat = 445.0 * markScale

        // Subtle dark aura behind elephant
        drawImageTopDown(
            ctx,
            brandMark,
            in: CGRect(
                x: markCenterX - markSize * 0.5,
                y: markCenterY - markSize * 0.5,
                width: markSize,
                height: markSize
            )
        )

        // Crisp "Moro" wordmark beneath elephant
        drawImageTopDown(ctx, wordmarkImg, in: CGRect(x: markCenterX - 260.0, y: 1020.0, width: 520.0, height: 150.0))

        // Wordless polarity pill indicator (Light <-> Dark swap at 6.0s and 12.0s!)
        let darkActive: Double
        if t < 5.75 {
            darkActive = 0.0
        } else if t < 6.25 {
            darkActive = smoothstep((t - 5.75) / 0.50)
        } else if t < 11.75 {
            darkActive = 1.0
        } else if t < 12.25 {
            darkActive = 1.0 - smoothstep((t - 11.75) / 0.50)
        } else {
            darkActive = 0.0
        }

        // Architectural hairline + 2 minimal polarity capsules
        ctx.setFillColor(rgba(255, 255, 255, 0.18))
        ctx.fill(CGRect(x: markCenterX - 40.0, y: 1185.0, width: 80.0, height: 2.5))

        let pillY: CGFloat = 1228.0
        let pillH: CGFloat = 10.0
        let wLight = CGFloat(lerp(66.0, 26.0, darkActive))
        let wDark = CGFloat(lerp(26.0, 66.0, darkActive))
        let gap: CGFloat = 16.0
        let totalW = wLight + gap + wDark
        let startX = markCenterX - totalW * 0.5

        ctx.addPath(roundedRectPath(CGRect(x: startX, y: pillY, width: wLight, height: pillH), radius: 5.0))
        ctx.setFillColor(rgba(255, 255, 255, CGFloat(lerp(0.92, 0.24, darkActive))))
        ctx.fillPath()

        ctx.addPath(roundedRectPath(CGRect(x: startX + wLight + gap, y: pillY, width: wDark, height: pillH), radius: 5.0))
        ctx.setFillColor(rgba(255, 255, 255, CGFloat(lerp(0.24, 0.92, darkActive))))
        ctx.fillPath()

        // 3. Dual Sculptural iPhones (Front Hero Slot <-> Back Recessed Slot)
        // Front Hero Slot: centerX = 2245, topY = 235, scale = 1.0, rot = 0°
        // Back Recessed Slot: centerX = 3075, topY = 435, scale = 0.875, rot = +2.8°
        let floatFront = sin(t * 2.0 * Double.pi / 3.0) * 5.0
        let floatBack = sin(t * 2.0 * Double.pi / 3.0 + 1.2) * 7.0

        // Compute swap progress p: 0.0 = Light front / Dark back; 1.0 = Dark front / Light back
        let swapP: Double
        if t < 5.65 {
            swapP = 0.0
        } else if t < 6.45 {
            swapP = springSettle((t - 5.65) / 0.80)
        } else if t < 11.65 {
            swapP = 1.0
        } else if t < 12.45 {
            swapP = 1.0 - springSettle((t - 11.65) / 0.80)
        } else {
            swapP = 0.0
        }

        // Split-layer inner scroll for Light & Dark screens
        // Scroll 0 -> 500px glides cleanly past first post text to frame the sunrise mountain + golden sunlit cat!
        let scrollLight: Double
        if t < 0.85 {
            scrollLight = 0.0
        } else if t < 5.35 {
            scrollLight = smoothstep((t - 0.85) / 4.50) * 500.0
        } else if t < 6.45 {
            scrollLight = 500.0
        } else if t < 11.4 {
            // Silently reset while recessed so it returns fresh on Swap 2!
            scrollLight = (1.0 - smoothstep((t - 7.5) / 2.5)) * 500.0
        } else {
            scrollLight = 0.0
        }

        let scrollDark: Double
        if t < 6.55 {
            scrollDark = 0.0
        } else if t < 11.35 {
            scrollDark = smoothstep((t - 6.55) / 4.80) * 500.0
        } else if t < 12.55 {
            scrollDark = 500.0
        } else {
            // Silently reset while recessed before loop wrap!
            scrollDark = (1.0 - smoothstep((t - 12.8) / 1.8)) * 500.0
        }

        // Arc lateral separation during mid-swap so phones sweep gracefully around each other!
        let midArc = sin(clamp(swapP, 0.0, 1.0) * Double.pi) // peaks 1.0 at swapP=0.5

        // Light Phone pose (Front at swapP=0, Back at swapP=1)
        let lightX = lerp(2245.0, 3075.0, swapP) - midArc * 135.0
        let lightY = lerp(235.0 + floatFront, 435.0 + floatBack, swapP) + midArc * 35.0
        let lightScale = lerp(1.0, 0.875, swapP)
        let lightRot = lerp(0.0, 2.8, swapP) - midArc * 1.4

        // Dark Phone pose (Back at swapP=0, Front at swapP=1)
        let darkX = lerp(3075.0, 2245.0, swapP) + midArc * 135.0
        let darkY = lerp(435.0 + floatBack, 235.0 + floatFront, swapP) - midArc * 25.0
        let darkScale = lerp(0.875, 1.0, swapP)
        let darkRot = lerp(2.8, 0.0, swapP) + midArc * 1.2

        let sheen = (t.truncatingRemainder(dividingBy: 5.0)) / 5.0

        // Depth sort: whichever phone is closer to Front draws second (on top)!
        let darkOnTop = swapP >= 0.5
        if darkOnTop {
            drawStudioPhone(
                in: ctx, geom: heroGeom,
                centerX: CGFloat(lightX), topY: CGFloat(lightY),
                scale: CGFloat(lightScale), rotationDeg: CGFloat(lightRot),
                opacity: 1.0,
                screenA: homeLight, scrollA: CGFloat(scrollLight),
                sheenPhase: CGFloat(sheen), shadowStrength: 0.72
            )
            drawStudioPhone(
                in: ctx, geom: heroGeom,
                centerX: CGFloat(darkX), topY: CGFloat(darkY),
                scale: CGFloat(darkScale), rotationDeg: CGFloat(darkRot),
                opacity: 1.0,
                screenA: homeDark, scrollA: CGFloat(scrollDark),
                sheenPhase: CGFloat((sheen + 0.35).truncatingRemainder(dividingBy: 1.0)), shadowStrength: 1.0
            )
        } else {
            drawStudioPhone(
                in: ctx, geom: heroGeom,
                centerX: CGFloat(darkX), topY: CGFloat(darkY),
                scale: CGFloat(darkScale), rotationDeg: CGFloat(darkRot),
                opacity: 1.0,
                screenA: homeDark, scrollA: CGFloat(scrollDark),
                sheenPhase: CGFloat((sheen + 0.35).truncatingRemainder(dividingBy: 1.0)), shadowStrength: 0.72
            )
            drawStudioPhone(
                in: ctx, geom: heroGeom,
                centerX: CGFloat(lightX), topY: CGFloat(lightY),
                scale: CGFloat(lightScale), rotationDeg: CGFloat(lightRot),
                opacity: 1.0,
                screenA: homeLight, scrollA: CGFloat(scrollLight),
                sheenPhase: CGFloat(sheen), shadowStrength: 1.0
            )
        }
    }
}

// MARK: - Search Placement Renderer (3840 × 2560, 12.0s, 30 fps = 360 frames, 10 locales + RTL)

final class SearchRenderer {
    let W = 3840
    let H = 2560
    let FPS = 30.0
    let totalFrames = 360
    let rtl: Bool
    let splitX: CGFloat

    let baseBG: CGImage
    let staticBrandOverlay: CGImage
    let beatTextCards: [CGImage] // 4 pre-rendered typography cards (kicker + headline + subtitle)
    let frontScreens: [SplitScreen] // [home-light, thread, inbox, home-dark]
    let backScreens: [SplitScreen]  // [home-dark, home-dark, home-dark, home-light]
    let heroGeom: PhoneGeometry
    let backGeom: PhoneGeometry

    init(copy: LocaleCopy, locale: String, assetsDir: String, screenshotsDir: String, iconPath: String) {
        self.rtl = copy.rtl
        self.splitX = copy.rtl ? CGFloat(3840 - 1498) : 1498.0

        let wm = loadCGImage("\(assetsDir)/moro-mark-white.png")
        let iconImg = loadCGImage(iconPath)

        self.baseBG = buildSplitBackground(
            width: W,
            height: H,
            splitX: splitX,
            rtl: rtl,
            watermark: wm,
            topScrimAlpha: 0.04
        )

        let homeLight = loadSplitScreen("\(screenshotsDir)/home-light.png", chromeSrcH: 334, collapsibleHeader: true, statusSrcH: 176)
        let homeDark = loadSplitScreen("\(screenshotsDir)/home-dark.png", chromeSrcH: 334, collapsibleHeader: true, statusSrcH: 176)
        let thread = loadSplitScreen("\(screenshotsDir)/thread.png", chromeSrcH: 344)
        let inbox = loadSplitScreen("\(screenshotsDir)/inbox.png", chromeSrcH: 344)

        self.frontScreens = [homeLight, thread, inbox, homeDark]
        self.backScreens = [homeDark, homeDark, homeDark, homeLight]

        // Sized so the full latest Liquid Glass '+' Compose Button (y=2425..2595) sits 100% inside frame
        // while keeping bottom floating tab bar / quick-reply bar (y>=2604) cleanly below canvas bottom!
        self.heroGeom = PhoneGeometry(outerW: 1266.0)
        self.backGeom = PhoneGeometry(outerW: 1070.0)

        // Pre-render steady left/right panel chrome (App Icon + bottom "Moro for Mastodon" lockup)
        let panelW = 1498
        let sctx = makeTopDownContext(width: panelW, height: H)
        let margin: CGFloat = 152.0
        let colW: CGFloat = CGFloat(panelW) - margin * 2.0 // 1194px

        // App Icon (124x124 squircle with subtle white hairline rim)
        let iconSize: CGFloat = 124.0
        let iconX: CGFloat = rtl ? (CGFloat(panelW) - margin - iconSize) : margin
        let iconRect = CGRect(x: iconX, y: 400.0, width: iconSize, height: iconSize)
        sctx.saveGState()
        sctx.addPath(roundedRectPath(iconRect, radius: 30.0))
        sctx.clip()
        drawImageTopDown(sctx, iconImg, in: iconRect)
        sctx.restoreGState()
        sctx.addPath(roundedRectPath(iconRect.insetBy(dx: 1.0, dy: 1.0), radius: 29.0))
        sctx.setStrokeColor(rgba(255, 255, 255, 0.24))
        sctx.setLineWidth(2.4)
        sctx.strokePath()

        // Bottom hairline + steady "Moro for Mastodon" signature
        let ruleW: CGFloat = 116.0
        let ruleX: CGFloat = rtl ? (CGFloat(panelW) - margin - ruleW) : margin
        sctx.setFillColor(rgba(255, 255, 255, 0.24))
        sctx.fill(CGRect(x: ruleX, y: 2010.0, width: ruleW, height: 2.5))

        drawAttributedText(
            in: sctx,
            string: copy.brand,
            font: NSFont.systemFont(ofSize: 48, weight: .semibold),
            color: NSColor(white: 1.0, alpha: 0.76),
            rect: CGRect(x: margin, y: 2060.0, width: colW, height: 76.0),
            alignment: rtl ? .right : .left,
            rtl: false, // Latin brand name reads LTR even when right-aligned in RTL panel
            kern: 0.4,
            lineHeightMultiple: 1.1
        )
        self.staticBrandOverlay = sctx.makeImage()!

        // Pre-render the 4 localized Beat typography overlays once via CoreText/AppKit
        var cards: [CGImage] = []
        let align: NSTextAlignment = rtl ? .right : .left
        let cjk = isCJK(locale)

        for beat in copy.beats {
            let bctx = makeTopDownContext(width: panelW, height: H)

            // 1. Kicker beside App Icon (vertically centered with 124px icon at y=400..524)
            let kickerFont = localizedFont(locale: locale, size: cjk ? 52.0 : (rtl ? 50.0 : 46.0), weight: .medium)
            let kickerX: CGFloat = rtl ? margin : (margin + iconSize + 38.0)
            let kickerW: CGFloat = colW - iconSize - 38.0
            let kickerText = (!cjk && !rtl) ? beat.kicker.uppercased() : beat.kicker
            drawAttributedText(
                in: bctx,
                string: kickerText,
                font: kickerFont,
                color: NSColor(white: 1.0, alpha: 0.78),
                rect: CGRect(x: kickerX, y: 432.0, width: kickerW, height: 74.0),
                alignment: align,
                rtl: rtl,
                kern: (!cjk && !rtl) ? 2.8 : 0.6,
                lineHeightMultiple: 1.1
            )

            // 2. Hero 2-Line Headline — bold billboard scale, unified size across both lines, zero overflow!
            let maxHeadSize: CGFloat = cjk ? 188.0 : (rtl ? 168.0 : 164.0)
            let headKern: CGFloat = (cjk || rtl) ? 0.0 : -3.6
            var headSize = maxHeadSize
            while headSize > 86.0 {
                let testFont = localizedFont(locale: locale, size: headSize, weight: .bold)
                let isRTL = copy.rtl
                let maxLineW = beat.lines.map {
                    measureSingleLine(string: $0, font: testFont, rtl: isRTL, kern: headKern).width
                }.max() ?? 0.0
                if maxLineW <= colW - 6.0 {
                    break
                }
                headSize -= 3.0
            }

            let headFont = localizedFont(locale: locale, size: headSize, weight: .bold)
            let lineStep = headSize * (rtl ? 1.34 : (cjk ? 1.24 : 1.15))
            let headStartY: CGFloat = 825.0

            for (idx, line) in beat.lines.enumerated() {
                let y = headStartY + CGFloat(idx) * lineStep
                drawAttributedText(
                    in: bctx,
                    string: line,
                    font: headFont,
                    color: NSColor.white,
                    rect: CGRect(x: margin, y: y, width: colW, height: lineStep * 1.25),
                    alignment: align,
                    rtl: rtl,
                    kern: headKern,
                    lineHeightMultiple: 1.05
                )
            }

            // 3. Crisp Silver Subtitle directly below headline (high legibility on iPhone Search card)
            let subY = headStartY + CGFloat(beat.lines.count) * lineStep + 68.0
            let subSize: CGFloat = cjk ? 62.0 : (rtl ? 62.0 : 58.0)
            let subFont = localizedFont(locale: locale, size: subSize, weight: .regular)
            drawAttributedText(
                in: bctx,
                string: beat.subtitle,
                font: subFont,
                color: NSColor(red: 178/255.0, green: 186/255.0, blue: 200/255.0, alpha: 1.0),
                rect: CGRect(x: margin, y: subY, width: colW, height: 260.0),
                alignment: align,
                rtl: rtl,
                kern: (cjk || rtl) ? 0.0 : -0.4,
                lineHeightMultiple: 1.36
            )

            cards.append(bctx.makeImage()!)
        }
        self.beatTextCards = cards
    }

    func renderFrame(_ frameIndex: Int, into ctx: CGContext) {
        let t = Double(frameIndex) / FPS // 0.0 .. 11.967s
        let loopPhase = t / 12.0

        // Determine beat state & beat-drop transition parameters!
        // Frame 0 is 100% pure poised Beat 0 (App Store Poster Frame!).
        // Cuts launch slightly before downbeats (2.88->3.24, 5.88->6.24, 8.88->9.24)
        // and final wrap completes cleanly over 11.62->11.98 so frame 0 == frame 360!
        var curBeat = 0
        var nextBeat: Int? = nil
        var transP = 0.0
        var beatLocalT = t

        if t < 2.88 {
            curBeat = 0; beatLocalT = t
        } else if t < 3.24 {
            curBeat = 0; nextBeat = 1; transP = easeInOutQuint((t - 2.88) / 0.36); beatLocalT = 2.88
        } else if t < 5.88 {
            curBeat = 1; beatLocalT = t - 3.0
        } else if t < 6.24 {
            curBeat = 1; nextBeat = 2; transP = easeInOutQuint((t - 5.88) / 0.36); beatLocalT = 2.88
        } else if t < 8.88 {
            curBeat = 2; beatLocalT = t - 6.0
        } else if t < 9.24 {
            curBeat = 2; nextBeat = 3; transP = easeInOutQuint((t - 8.88) / 0.36); beatLocalT = 2.88
        } else if t < 11.62 {
            curBeat = 3; beatLocalT = t - 9.0
        } else {
            curBeat = 3; nextBeat = 0; transP = easeInOutQuint((t - 11.62) / 0.36); beatLocalT = 2.62
        }

        // 1. Static Split Monochrome Stage + living obsidian gallery sheen
        let darkRect = rtl
            ? CGRect(x: splitX, y: 0, width: CGFloat(W) - splitX, height: CGFloat(H))
            : CGRect(x: 0, y: 0, width: splitX, height: CGFloat(H))
        drawImageTopDown(ctx, baseBG, in: CGRect(x: 0, y: 0, width: CGFloat(W), height: CGFloat(H)))
        drawObsidianSheen(in: ctx, darkRect: darkRect, phase: loopPhase)

        // 2. Left/Right Obsidian Panel Chrome + Kinetic 4-Beat Progress Pills + Typography
        let panelOriginX: CGFloat = rtl ? splitX : 0.0
        let panelRect = CGRect(x: panelOriginX, y: 0, width: 1498.0, height: CGFloat(H))
        drawImageTopDown(ctx, staticBrandOverlay, in: panelRect)

        // Dynamic 4-beat capsule progress indicator (y = 635)
        let margin: CGFloat = 152.0
        let pillY: CGFloat = 636.0
        let pillH: CGFloat = 10.0
        let pillGap: CGFloat = 20.0
        var pillWidths: [CGFloat] = []
        var pillAlphas: [CGFloat] = []
        for i in 0..<4 {
            var active = (i == curBeat) ? 1.0 : 0.0
            if let nb = nextBeat {
                if i == curBeat { active = 1.0 - transP }
                else if i == nb { active = transP }
            }
            pillWidths.append(CGFloat(lerp(44.0, 132.0, active)))
            pillAlphas.append(CGFloat(lerp(0.22, 0.96, active)))
        }
        if rtl {
            var cursor = panelOriginX + 1498.0 - margin
            for i in 0..<4 {
                let pw = pillWidths[i]
                cursor -= pw
                ctx.addPath(roundedRectPath(CGRect(x: cursor, y: pillY, width: pw, height: pillH), radius: 5.0))
                ctx.setFillColor(rgba(255, 255, 255, pillAlphas[i]))
                ctx.fillPath()
                cursor -= pillGap
            }
        } else {
            var cursor = panelOriginX + margin
            for i in 0..<4 {
                let pw = pillWidths[i]
                ctx.addPath(roundedRectPath(CGRect(x: cursor, y: pillY, width: pw, height: pillH), radius: 5.0))
                ctx.setFillColor(rgba(255, 255, 255, pillAlphas[i]))
                ctx.fillPath()
                cursor += pw + pillGap
            }
        }

        // Animated Beat Typography Card(s)
        if let nb = nextBeat {
            // Outgoing text glides subtly up & fades out
            let outAlpha = clamp(1.0 - transP * 1.45, 0.0, 1.0)
            if outAlpha > 0.005 {
                ctx.saveGState()
                ctx.setAlpha(CGFloat(outAlpha))
                drawImageTopDown(ctx, beatTextCards[curBeat], in: panelRect.offsetBy(dx: 0, dy: CGFloat(-transP * 34.0)))
                ctx.restoreGState()
            }
            // Incoming text glides silkily up from +38px into resting anchor
            let inP = clamp((transP - 0.18) / 0.82, 0.0, 1.0)
            let inEase = easeOutCubic(inP)
            if inEase > 0.005 {
                ctx.saveGState()
                ctx.setAlpha(CGFloat(inEase))
                drawImageTopDown(ctx, beatTextCards[nb], in: panelRect.offsetBy(dx: 0, dy: CGFloat((1.0 - inEase) * 40.0)))
                ctx.restoreGState()
            }
        } else {
            drawImageTopDown(ctx, beatTextCards[curBeat], in: panelRect)
        }

        // 3. Oversized Sculptural Dual Titanium iPhones on 61% Architectural Stone Stage
        // LTR: Foreground Hero at centerX=2460 (x=1810..3110), Recessed Secondary at centerX=3330 (x=2785..3875, rot=+3.0°)
        // RTL: Mirrored cleanly across 3840!
        let frontCenterX: CGFloat = rtl ? (3840.0 - 2460.0) : 2460.0
        let backCenterX: CGFloat = rtl ? (3840.0 - 3330.0) : 3330.0
        let backRot: CGFloat = rtl ? -3.0 : 3.0

        // Gentle 80 BPM living parallax float (exact 3.0s period, zero offset at frame 0!)
        let floatFront = sin(t * 2.0 * Double.pi / 3.0) * 8.0
        let floatBack = sin(t * 2.0 * Double.pi / 3.0 + 0.9) * 11.0

        // Tactile kinetic beat-drop nudge when transitioning between chapters!
        let kickBump = nextBeat != nil ? sin(transP * Double.pi) : 0.0
        let frontTopY: CGFloat = 198.0 + CGFloat(floatFront) + CGFloat(kickBump * 16.0)
        let frontScale: CGFloat = 1.0 - CGFloat(kickBump * 0.012)
        let backTopY: CGFloat = 432.0 + CGFloat(floatBack) - CGFloat(kickBump * 10.0)

        // Keep Home (Beat 0/3) and Thread (Beat 1) scroll=0 so floating Liquid Glass '+' & quick-reply bars
        // stay anchored cleanly at the bottom edge; gently glide Inbox (Beat 2) where content sits above the tab bar!
        func holdScroll(_ localT: Double, beat: Int) -> CGFloat {
            guard beat == 2 else { return 0.0 }
            let u = clamp((localT - 0.35) / 2.25, 0.0, 1.0)
            return CGFloat(smoothstep(u) * 68.0)
        }

        let scrollFrontA = holdScroll(beatLocalT, beat: curBeat)
        let scrollFrontB: CGFloat = 0.0
        let sheen = (t.truncatingRemainder(dividingBy: 3.0)) / 3.0

        // Draw Recessed Secondary Phone first
        let backNextScreen: SplitScreen? = nextBeat != nil ? backScreens[nextBeat!] : nil
        let backSame = (nextBeat != nil && backScreens[curBeat].full === backScreens[nextBeat!].full)
        drawStudioPhone(
            in: ctx,
            geom: backGeom,
            centerX: backCenterX,
            topY: backTopY,
            scale: 1.0,
            rotationDeg: backRot,
            opacity: 1.0,
            screenA: backScreens[curBeat],
            scrollA: 0.0,
            screenB: backSame ? nil : backNextScreen,
            scrollB: 0.0,
            crossfadeB: backSame ? 0.0 : CGFloat(transP),
            slideBOffset: 60.0,
            sheenPhase: CGFloat((sheen + 0.45).truncatingRemainder(dividingBy: 1.0)),
            shadowStrength: 0.72
        )

        // Draw Foreground Hero Phone on top
        drawStudioPhone(
            in: ctx,
            geom: heroGeom,
            centerX: frontCenterX,
            topY: frontTopY,
            scale: frontScale,
            rotationDeg: 0.0,
            opacity: 1.0,
            screenA: frontScreens[curBeat],
            scrollA: scrollFrontA,
            screenB: nextBeat != nil ? frontScreens[nextBeat!] : nil,
            scrollB: scrollFrontB,
            crossfadeB: CGFloat(transP),
            slideBOffset: 92.0,
            sheenPhase: CGFloat(sheen),
            shadowStrength: 1.0
        )
    }
}

// MARK: - Parallel Frame Streamer

func streamFrames(
    width: Int,
    height: Int,
    totalFrames: Int,
    render: @escaping (Int, CGContext) -> Void
) {
    let bytesPerFrame = width * height * 4
    let batchSize = max(1, min(8, ProcessInfo.processInfo.activeProcessorCount))
    let pool = (0..<batchSize).map { _ in UnsafeMutableRawPointer.allocate(byteCount: bytesPerFrame, alignment: 64) }
    defer { pool.forEach { $0.deallocate() } }

    var f = 0
    while f < totalFrames {
        let count = min(batchSize, totalFrames - f)
        let startF = f
        DispatchQueue.concurrentPerform(iterations: count) { slot in
            let buf = pool[slot]
            let ctx = makeTopDownContext(width: width, height: height, data: buf)
            render(startF + slot, ctx)
        }
        for slot in 0..<count {
            writeAll(STDOUT_FILENO, pool[slot], bytesPerFrame)
        }
        f += count
    }
}

// MARK: - Entry Point

let args = CommandLine.arguments
guard args.count >= 2 else {
    fputs("Usage:\n  render header <assetsDir> <screenshotsDir> <poster|keyframes|stream> [outPath]\n  render search <copyJson> <locale> <assetsDir> <screenshotsDir> <iconPng> <poster|beats|stream> [outPath]\n", stderr)
    exit(2)
}

let cmd = args[1]

if cmd == "header" {
    guard args.count >= 5 else { exit(2) }
    let assetsDir = args[2]
    let shotsDir = args[3]
    let mode = args[4]
    let renderer = HeaderRenderer(assetsDir: assetsDir, screenshotsDir: shotsDir)

    switch mode {
    case "poster":
        let outPath = args[5]
        let ctx = makeTopDownContext(width: renderer.W, height: renderer.H)
        renderer.renderFrame(0, into: ctx)
        savePNG(ctx.makeImage()!, to: outPath)
    case "keyframes":
        let outDir = args[5]
        let frames = [0, 90, 178, 196, 300, 376, 449]
        for fi in frames {
            let ctx = makeTopDownContext(width: renderer.W, height: renderer.H)
            renderer.renderFrame(fi, into: ctx)
            savePNG(ctx.makeImage()!, to: "\(outDir)/frame-\(String(format: "%03d", fi)).png")
        }
    case "stream":
        streamFrames(width: renderer.W, height: renderer.H, totalFrames: renderer.totalFrames) { fi, ctx in
            renderer.renderFrame(fi, into: ctx)
        }
    default:
        fputs("Unknown mode \(mode)\n", stderr)
        exit(2)
    }
} else if cmd == "search" {
    guard args.count >= 8 else { exit(2) }
    let copyPath = args[2]
    let locale = args[3]
    let assetsDir = args[4]
    let shotsDir = args[5]
    let iconPath = args[6]
    let mode = args[7]

    let data = try Data(contentsOf: URL(fileURLWithPath: copyPath))
    let allCopy = try JSONDecoder().decode([String: LocaleCopy].self, from: data)
    guard let locCopy = allCopy[locale] else {
        fputs("ERROR: Unknown locale \(locale)\n", stderr)
        exit(1)
    }

    let renderer = SearchRenderer(
        copy: locCopy,
        locale: locale,
        assetsDir: assetsDir,
        screenshotsDir: shotsDir,
        iconPath: iconPath
    )

    switch mode {
    case "poster":
        let outPath = args[8]
        let ctx = makeTopDownContext(width: renderer.W, height: renderer.H)
        renderer.renderFrame(0, into: ctx)
        savePNG(ctx.makeImage()!, to: outPath)
    case "beats":
        let outDir = args[8]
        let marks = [0, 105, 195, 285]
        for (idx, fi) in marks.enumerated() {
            let ctx = makeTopDownContext(width: renderer.W, height: renderer.H)
            renderer.renderFrame(fi, into: ctx)
            savePNG(ctx.makeImage()!, to: "\(outDir)/beat-\(idx).png")
        }
    case "stream":
        streamFrames(width: renderer.W, height: renderer.H, totalFrames: renderer.totalFrames) { fi, ctx in
            renderer.renderFrame(fi, into: ctx)
        }
    default:
        fputs("Unknown mode \(mode)\n", stderr)
        exit(2)
    }
} else {
    fputs("Unknown command \(cmd)\n", stderr)
    exit(2)
}
