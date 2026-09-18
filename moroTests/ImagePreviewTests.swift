import Testing
import UIKit
@testable import moro

@MainActor
struct ImagePreviewTests {
    @Test func emptyDescriptionsDoNotProduceAnAltEntry() {
        for value in [nil, "", " \n\t "] as [String?] {
            #expect(ImagePreviewView.descriptionText(value) == nil)
        }
        #expect(ImagePreviewView.descriptionText("\n Description \n") == "Description")
    }

    @Test func aLongPageFitsEntirelyThenDoubleTapsToScreenWidth() {
        let view = makeView()
        #expect(abs(view.imageView.frame.height - 800) < 1)
        #expect(abs(view.imageView.frame.width - 100) < 1)
        view.toggleZoom(at: CGPoint(x: 300, y: 2400), animated: false)
        #expect(abs(view.imageView.frame.width - 400) < 1)
        #expect(abs(view.imageView.frame.height - 3200) < 1)
        #expect(view.contentOffset.y > 0)
        view.toggleZoom(at: .zero, animated: false)
        #expect(view.isAtMinimumZoom)
        #expect(abs(view.imageView.frame.height - 800) < 1)
    }

    @Test func doubleTapKeepsTheChosenReadingLocationVisible() {
        let view = makeView()
        let point = CGPoint(x: 300, y: 3700)
        view.toggleZoom(at: point, animated: false)
        let visiblePoint = view.convert(point, from: view.imageView)
        #expect(view.bounds.contains(visiblePoint))
        #expect(abs(visiblePoint.y - view.bounds.midY) < 1)
    }

    @Test func layoutAndDescriptionUpdatesKeepTheReadingPosition() {
        let view = makeView()
        let url = URL(string: "https://image-preview-fixture.invalid/position.png")!
        view.configure(url: url, altText: "Description")
        view.cancelLoading()
        view.display(makeImage())
        view.layoutIfNeeded()
        view.toggleZoom(at: CGPoint(x: 300, y: 3000), animated: false)
        let scale = view.zoomScale
        let offset = view.contentOffset
        view.configure(url: url, altText: "Updated description")
        view.setNeedsLayout()
        view.layoutIfNeeded()
        #expect(view.zoomScale == scale)
        #expect(view.contentOffset == offset)
        #expect(view.imageView.accessibilityLabel == "Updated description")
    }

    @Test func rotationKeepsTheReadingAnchorAndUsesValidScrollBounds() {
        let view = makeView()
        view.toggleZoom(at: CGPoint(x: 300, y: 2400), animated: false)
        let oldCenter = (view.contentOffset.y + view.bounds.height / 2) / view.zoomScale
        view.frame.size = CGSize(width: 800, height: 400)
        view.layoutIfNeeded()
        let center = (view.contentOffset.y + view.bounds.height / 2) / view.zoomScale
        #expect(abs(oldCenter - center) < 1)
        #expect(view.contentOffset == view.boundedOffset(view.contentOffset))
    }

    @Test func panningBoundsIncludeBothEndsWithoutLosingTheImage() {
        let view = makeView()
        view.toggleZoom(at: CGPoint(x: 300, y: 2400), animated: false)
        let start = view.boundedOffset(CGPoint(x: -10000, y: -10000))
        let end = view.boundedOffset(CGPoint(x: 10000, y: 10000))
        #expect(start.y == 0)
        #expect(abs(end.y - 2400) < 1)
        #expect(start.x == 0 && end.x == 0)
    }

    @Test func decodingPreservesLongTextResolutionAndBoundsLargeImages() throws {
        let longData = try #require(makeImage().pngData())
        let longImage = try #require(ImagePreviewImageCoder.shared.decodedImage(with: longData))
        #expect(longImage.size.width == 600)
        #expect(longImage.size.height == 4800)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let largeData = UIGraphicsImageRenderer(size: CGSize(width: 4000, height: 4000), format: format).jpegData(withCompressionQuality: 0.6) { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 4000, height: 4000))
        }
        let largeImage = try #require(ImagePreviewImageCoder.shared.decodedImage(with: largeData))
        let pixels = try #require(largeImage.cgImage)
        #expect(Double(pixels.width * pixels.height) <= ImagePreviewImageCoder.maximumPixelCount)
    }

    private func makeView() -> ImagePreviewScrollView {
        let view = ImagePreviewScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        view.display(makeImage())
        view.layoutIfNeeded()
        return view
    }

    private func makeImage() -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: 600, height: 4800), format: format).image { context in
            UIColor.white.setFill()
            context.fill(CGRect(x: 0, y: 0, width: 600, height: 4800))
        }
    }
}
