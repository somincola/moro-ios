//
//  ImagePreviewSwapTests.swift
//  moroTests
//
//  The viewer opens on the timeline's smaller image and swaps in the full size when it
//  arrives; the swap must not move anything on screen.
//

import Testing
import UIKit
@testable import moro

@MainActor
struct ImagePreviewSwapTests {
    private func image(_ size: CGSize) -> UIImage {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(origin: .zero, size: size))
        }
    }

    private func makeView(showing preview: UIImage) -> ImagePreviewScrollView {
        let view = ImagePreviewScrollView(frame: CGRect(x: 0, y: 0, width: 400, height: 800))
        view.display(preview)
        view.layoutIfNeeded()
        return view
    }

    /// The image's on-screen rectangle, in the scroll view's visible coordinates.
    private func visibleRect(_ view: ImagePreviewScrollView) -> CGRect {
        view.imageView.frame.offsetBy(dx: -view.contentOffset.x, dy: -view.contentOffset.y)
    }

    @Test func overviewLooksTheSameAfterTheFullImageArrives() {
        let view = makeView(showing: image(CGSize(width: 320, height: 240)))
        let before = visibleRect(view)

        view.replaceDisplayedImage(with: image(CGSize(width: 4000, height: 3000)))

        #expect(view.imageView.image?.size == CGSize(width: 4000, height: 3000))
        #expect(view.isAtMinimumZoom)
        let after = visibleRect(view)
        #expect(abs(after.minX - before.minX) < 0.5 && abs(after.minY - before.minY) < 0.5)
        #expect(abs(after.width - before.width) < 0.5 && abs(after.height - before.height) < 0.5)
    }

    @Test func aZoomedReaderKeepsTheirZoomAndPosition() {
        let view = makeView(showing: image(CGSize(width: 150, height: 1500)))
        view.setZoomScale(view.minimumZoomScale * 3, animated: false)
        view.contentOffset = view.boundedOffset(CGPoint(x: 100, y: 900))
        let before = visibleRect(view)

        view.replaceDisplayedImage(with: image(CGSize(width: 600, height: 6000)))

        #expect(abs(view.zoomScale / view.minimumZoomScale - 3) < 0.01)
        let after = visibleRect(view)
        #expect(abs(after.minX - before.minX) < 1 && abs(after.minY - before.minY) < 1)
        #expect(abs(after.width - before.width) < 1 && abs(after.height - before.height) < 1)
    }

    @Test func aDifferentShapeStartsOverAtTheOverview() {
        let view = makeView(showing: image(CGSize(width: 300, height: 300)))
        view.setZoomScale(view.minimumZoomScale * 2, animated: false)

        view.replaceDisplayedImage(with: image(CGSize(width: 1600, height: 900)))
        view.layoutIfNeeded()

        #expect(view.imageView.image?.size == CGSize(width: 1600, height: 900))
        #expect(view.isAtMinimumZoom)
    }
}
