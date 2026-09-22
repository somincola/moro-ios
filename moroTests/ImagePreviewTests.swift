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

    @Test func shortDismissDragsKeepTheImageViewportAndZoomStable() {
        let page = ImagePreviewPageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        page.layoutIfNeeded()
        let view = page.scrollView
        view.display(makeImage())
        view.layoutIfNeeded()
        let viewport = view.bounds.size
        let zoom = view.zoomScale
        let offset = view.contentOffset
        let originalFrame = view.imageView.convert(view.imageView.bounds, to: page)

        for distance: CGFloat in [0, 2, 5, 10, 20, 50, 100, 20, 0] {
            page.updateDismissDrag(distance, ended: false)
            page.setNeedsLayout()
            page.layoutIfNeeded()
            view.layoutIfNeeded()
            #expect(view.bounds.size == viewport)
            #expect(view.zoomScale == zoom)
            #expect(view.contentOffset == offset)
            let frame = view.imageView.convert(view.imageView.bounds, to: page)
            #expect(abs(frame.midY - originalFrame.midY - distance) < 0.01)
        }
        page.reduceMotion = true
        page.updateDismissDrag(0, ended: true)
        #expect(view.transform == .identity)
        #expect(view.imageView.convert(view.imageView.bounds, to: page) == originalFrame)
    }

    @Test func reduceMotionDismissalOnlyTranslatesAndCanBeReset() {
        let page = ImagePreviewPageView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        page.reduceMotion = true
        page.layoutIfNeeded()
        page.updateDismissDrag(20, ended: false)
        #expect(page.scrollView.transform == CGAffineTransform(translationX: 0, y: 20))
        page.resetDismissDrag()
        page.updateDismissDrag(5, ended: false)
        #expect(page.scrollView.transform == CGAffineTransform(translationX: 0, y: 5))
        page.updateDismissDrag(0, ended: true)
        #expect(page.scrollView.transform == .identity)
    }

    @Test func zoomedImageRejectsDismissalAtTouchDown() throws {
        let view = makeView()
        let dismissPan = try #require(view.gestureRecognizers?.compactMap { $0 as? UIPanGestureRecognizer }
            .first { $0 !== view.panGestureRecognizer })
        #expect(view.gestureRecognizer(dismissPan, shouldReceive: UITouch()))
        view.toggleZoom(at: CGPoint(x: 300, y: 2400), animated: false)
        #expect(!view.gestureRecognizer(dismissPan, shouldReceive: UITouch()))
        #expect(view.gestureRecognizerShouldBegin(view.panGestureRecognizer))
        view.toggleZoom(at: .zero, animated: false)
        #expect(view.gestureRecognizer(dismissPan, shouldReceive: UITouch()))
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
