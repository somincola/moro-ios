//
//  StateAndMascotTests.swift
//  moroTests
//
//  Unit tests for MoroMascotGeometry, MoroErrorCopy, EmptyStateSpec, and MoroNoticePill.
//

import CoreGraphics
import Foundation
import SwiftUI
import Testing
import UIKit
@testable import moro

@Suite("StateAndMascotTests")
struct StateAndMascotTests {
    @Test func allMascotExpressionsProduceValidGeometry() {
        let size = CGSize(width: 58, height: 58)
        for expression in MoroMascotExpression.allCases {
            let layers = MoroMascotGeometry.layers(for: expression, in: size)
            #expect(!layers.primaryStroke.isEmpty)
            #expect(!layers.secondaryStroke.isEmpty)
            if expression == .thinking {
                #expect(layers.thinkingDots.count == 3)
                #expect(layers.thinkingDotRadii.count == 3)
            } else {
                #expect(layers.thinkingDots.isEmpty)
            }
        }
    }

    @Test func emptyStateSpecInfersAndRespectsExplicitMascot() {
        let calm = EmptyStateSpec(icon: "megaphone", title: "Empty", message: "None")
        #expect(calm.resolvedMascot == .calm)

        let curious = EmptyStateSpec(icon: "magnifyingglass", title: "No match", message: "Try again")
        #expect(curious.resolvedMascot == .curious)

        let filterCurious = EmptyStateSpec(icon: "line.3.horizontal.decrease.circle", title: "Filtered", message: "None")
        #expect(filterCurious.resolvedMascot == .curious)

        let resting = EmptyStateSpec(icon: "megaphone.slash", title: "Unsupported", message: "None")
        #expect(resting.resolvedMascot == .resting)

        let explicit = EmptyStateSpec(icon: "megaphone", title: "Custom", message: "None", mascot: .offline)
        #expect(explicit.resolvedMascot == .offline)
    }

    @Test func errorCopyMapsSystemAndNetworkingErrorsToLocalizedHumanCopy() {
        #expect(
            MoroErrorCopy.message(for: URLError(.notConnectedToInternet))
                == MoroL10n.AppError.networkUnavailable
        )
        #expect(
            MoroErrorCopy.message(for: URLError(.timedOut))
                == MoroL10n.AppError.timeout
        )
        #expect(
            MoroErrorCopy.message(for: APIError.rateLimited(retryAfter: 30))
                == MoroL10n.AppError.rateLimited
        )

        #expect(
            MoroErrorCopy.sanitized("The operation couldn’t be completed. (NSURLErrorDomain error -1009.)")
                == MoroL10n.AppError.recoveryTryAgain
        )
        #expect(
            MoroErrorCopy.sanitized("   ")
                == MoroL10n.AppError.recoveryTryAgain
        )
        #expect(
            MoroErrorCopy.sanitized("Instance maintenance in progress")
                == "Instance maintenance in progress"
        )
    }

    @MainActor
    @Test func noticePillSupportsOptionalIconForInfoToasts() {
        let infoPill = MoroNoticePill(text: "Copied link")
        #expect(infoPill.icon == nil)
        #expect(infoPill.text == "Copied link")

        let successPill = MoroNoticePill(icon: "checkmark", text: "Saved")
        #expect(successPill.icon == "checkmark")
    }

    @MainActor
    @Test func renderVisualShowcaseSnapshots() throws {
        guard let outputDir = ProcessInfo.processInfo.environment["MORO_VISUAL_EXPORT_DIR"], !outputDir.isEmpty else {
            return
        }
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let theme = MoroTheme(colorScheme: scheme)
            let sheet = VStack(spacing: 24) {
                HStack(spacing: 18) {
                    ForEach(MoroMascotExpression.allCases, id: \.self) { expression in
                        VStack(spacing: 6) {
                            MoroMascotView(expression: expression, size: 58, animated: false)
                            Text(String(describing: expression))
                                .font(.caption2)
                                .foregroundStyle(theme.colors.textSecondary)
                        }
                    }
                }
                .padding(.top, 8)

                Divider()

                HStack(spacing: 12) {
                    MoroNoticePill(text: "已隐藏该用户在时间线上的转嘟")
                    MoroNoticePill(icon: "checkmark", text: "已保存")
                    MoroNoticePill(icon: "exclamationmark", text: "操作失败")
                }

                Divider()

                HStack(alignment: .top, spacing: 16) {
                    EmptyStateView(
                        spec: EmptyStateSpec(
                            icon: "megaphone",
                            title: "暂时没有公告",
                            message: "实例发布新公告时，会安静地出现在这里。",
                            actionTitle: "刷新",
                            action: {}
                        )
                    )
                    .frame(width: 240, height: 220)

                    ErrorStateView(
                        spec: ErrorStateSpec(
                            title: "暂时没能加载",
                            message: "请检查网络连接后重试。",
                            actionTitle: "重试",
                            action: {}
                        )
                    )
                    .frame(width: 240, height: 220)
                }

                Divider()

                VStack(spacing: 10) {
                    MoroInlineNoticeBanner(
                        message: "当前展示缓存内容，网络恢复后可刷新。",
                        tone: .neutral,
                        actionTitle: "重试",
                        action: {}
                    )
                    MoroInlineNoticeBanner(
                        message: "通知暂时没能加载，请稍后再试。",
                        tone: .error,
                        actionTitle: "重试",
                        action: {}
                    )
                    PaginationFooter(isLoadingMore: true, didFail: false, onRetry: {})
                    PaginationFooter(isLoadingMore: false, didFail: true, onRetry: {})
                }
                .frame(width: 440)
            }
            .padding(24)
            .background(theme.colors.surfaceBase)
            .environment(\.colorScheme, scheme)
            .moroTheme(theme)

            let renderer = ImageRenderer(content: sheet)
            renderer.scale = 3.0
            let uiImage = try #require(renderer.uiImage)
            let data = try #require(uiImage.pngData())
            let url = URL(fileURLWithPath: outputDir).appendingPathComponent("state-showcase-\(name).png")
            try data.write(to: url)
        }
    }
}
