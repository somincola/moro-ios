import AppKit
import CoreText
import ImageIO
import UniformTypeIdentifiers

// Each 310 × 200 cell is placed at the same point in the left column of the film.
let args = CommandLine.arguments
guard args.count == 4 else { fatalError("Usage: captions copy.json locale output.png") }
let locale = args[2]
let copy = try JSONDecoder().decode([String: [[String]]].self,
    from: Data(contentsOf: URL(fileURLWithPath: args[1])))
guard let captions = copy[locale], captions.count == 4, captions.allSatisfy({ $0.count == 3 })
else { fatalError("Missing four two-line captions for " + locale) }

let cell = CGSize(width: 310, height: 200)
let scale = 3
let width = Int(cell.width) * 2 * scale
let height = Int(cell.height) * 2 * scale
let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                        space: CGColorSpace(name: CGColorSpace.sRGB)!,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
context.scaleBy(x: CGFloat(scale), y: CGFloat(scale))
context.setShouldSmoothFonts(false)
let rtl = locale == "ar-SA"
let east = locale.hasPrefix("zh") || locale == "ja"
let regularInk = NSColor(srgbRed: 0.121, green: 0.162, blue: 0.207, alpha: 1)
let softInk = NSColor(srgbRed: 0.275, green: 0.311, blue: 0.349, alpha: 1)

func typeset(_ text: String, points: CGFloat, isTitle: Bool) -> CTLine {
    let weight: NSFont.Weight = isTitle ? .medium : .regular
    let family: String?
    switch locale {
    case "zh-Hans": family = isTitle ? "PingFangSC-Medium" : "PingFangSC-Regular"
    case "zh-Hant": family = isTitle ? "PingFangTC-Medium" : "PingFangTC-Regular"
    case "ja": family = isTitle ? "HiraginoSans-W5" : "HiraginoSans-W3"
    default: family = nil
    }
    let font = family.flatMap { NSFont(name: $0, size: points) } ?? .systemFont(ofSize: points, weight: weight)
    let paragraph = NSMutableParagraphStyle()
    paragraph.baseWritingDirection = rtl ? .rightToLeft : .leftToRight
    var style: [NSAttributedString.Key: Any] = [
        .font: font, .paragraphStyle: paragraph, .foregroundColor: isTitle ? softInk : regularInk
    ]
    if !rtl { style[.kern] = (east ? -0.015 : -0.029) * points }
    return CTLineCreateWithAttributedString(NSAttributedString(string: text, attributes: style))
}

func inkBounds(_ line: CTLine) -> CGRect { CTLineGetBoundsWithOptions(line, .useGlyphPathBounds) }

// Set both lines together so a short second line keeps the same optical size and baseline spacing.
func pointSize(_ lines: ArraySlice<String>, ideal: CGFloat, available: CGFloat, isTitle: Bool) -> CGFloat {
    let longest = lines.map { inkBounds(typeset($0, points: ideal, isTitle: isTitle)).width }.max()!
    return ideal * min(1, available / max(1, longest))
}

for (index, content) in captions.enumerated() {
    let origin = CGPoint(x: CGFloat(index % 2) * cell.width, y: CGFloat(index / 2) * cell.height)
    let leading: CGFloat = 5, trailing: CGFloat = 296
    let titleLeading: CGFloat = 67
    let titleWidth = trailing - titleLeading
    let titleSize = pointSize(content[0...0], ideal: east ? 31 : 32, available: titleWidth, isTitle: true)
    let bodySize = pointSize(content[1...2], ideal: east ? 41 : 42, available: trailing - leading, isTitle: false)
    func draw(_ text: String, points: CGFloat, title: Bool, baseline: CGFloat) {
        let line = typeset(text, points: points, isTitle: title)
        let bounds = inkBounds(line)
        let x = title ? titleLeading : (rtl ? trailing - bounds.width : leading)
        context.textPosition = CGPoint(x: origin.x + x - bounds.minX,
                                       y: cell.height * 2 - origin.y - baseline)
        CTLineDraw(line, context)
    }
    draw(content[0], points: titleSize, title: true, baseline: 47)
    draw(content[1], points: bodySize, title: false, baseline: 118)
    draw(content[2], points: bodySize, title: false, baseline: 168)
}
let destination = CGImageDestinationCreateWithURL(URL(fileURLWithPath: args[3]) as CFURL,
                                                  UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write caption atlas") }
