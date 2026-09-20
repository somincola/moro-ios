#if DEBUG
import SDWebImage
import SwiftUI

/// Local fixtures exercise the real viewer and disk-decoding path without an account or network.
struct ImagePreviewHarnessView: View {
    @State private var attachments: [Status.Attachment] = []
    @State private var showsPreview = false
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var initialIndex: Int {
        Int(ProcessInfo.processInfo.environment["UITEST_IMAGE_INDEX"] ?? "0") ?? 0
    }

    var body: some View {
        Button("Open image viewer") { showsPreview = true }
            .accessibilityIdentifier("imagePreview.open")
            .disabled(attachments.isEmpty)
            .task {
                guard attachments.isEmpty else { return }
                attachments = await Self.makeAttachments()
                showsPreview = true
            }
            .fullScreenCover(isPresented: $showsPreview) {
                ImagePreviewView(attachments: attachments, initialIndex: initialIndex)
                    .moroTheme(MoroTheme(colorScheme: colorScheme, dynamicTypeSize: dynamicTypeSize))
                    .environment(\.dynamicTypeSize, dynamicTypeSize)
            }
    }

    private static func makeAttachments() async -> [Status.Attachment] {
        let defaultDescription = "A long reading page with numbered chapters and a green END marker at the bottom.\n\n"
            + String(repeating: "图片描述可以单独阅读和复制，关闭后应回到原来的图片阅读位置。\n", count: 18)
            + "\n描述结束。"
        let descriptions: [String?] = [nil,
            ProcessInfo.processInfo.environment["UITEST_ALT_TEXT"] ?? defaultDescription,
            " \n\t "]
        var result: [Status.Attachment] = []
        for index in 0..<3 {
            let size = index == 2 ? CGSize(width: 1600, height: 1000) : CGSize(width: 600, height: 4800)
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            let image = UIGraphicsImageRenderer(size: size, format: format).image { context in
                UIColor(red: 0.96, green: 0.95, blue: 0.91, alpha: 1).setFill()
                context.fill(CGRect(origin: .zero, size: size))
                if index == 2 {
                    UIColor.systemIndigo.setFill()
                    context.fill(CGRect(x: 40, y: 40, width: size.width - 80, height: size.height - 80))
                    draw("03 / WIDE IMAGE", at: CGPoint(x: 180, y: 420), size: 110, color: .white)
                } else {
                    draw("长图阅读 / LONG READ", at: CGPoint(x: 36, y: 36), size: 36)
                    draw(index == 0 ? "01 · 没有 ALT" : "02 · 有 ALT", at: CGPoint(x: 36, y: 100), size: 24)
                    for row in 0..<48 {
                        let y = CGFloat(180 + row * 90)
                        draw(String(format: "%02d  /  阅读段落", row + 1), at: CGPoint(x: 36, y: y), size: 26)
                        draw("放大看清文字，上下连续阅读。", at: CGPoint(x: 36, y: y + 38), size: 22,
                            color: .darkGray)
                    }
                    UIColor(red: 0.13, green: 0.40, blue: 0.30, alpha: 1).setFill()
                    context.fill(CGRect(x: 0, y: 4600, width: 600, height: 200))
                    draw("END · 图像底部完整可见", at: CGPoint(x: 36, y: 4670), size: 32, color: .white)
                }
            }
            let url = URL(string: "https://image-preview-fixture.invalid/v2/page-\(index).png")!
            await withCheckedContinuation { continuation in
                SDImageCache.shared.store(image, imageData: image.pngData(), forKey: url.absoluteString,
                    toDisk: true) { continuation.resume() }
            }
            result.append(Status.Attachment(id: "page-\(index)", type: "image", url: url,
                description: descriptions[index]))
        }
        SDImageCache.shared.clearMemory()
        return result
    }

    private static func draw(_ text: String, at point: CGPoint, size: CGFloat, color: UIColor = .black) {
        (text as NSString).draw(at: point, withAttributes: [
            .font: UIFont.systemFont(ofSize: size, weight: .medium), .foregroundColor: color,
        ])
    }
}
#endif
