//
//  MoroSceneTests.swift
//  moroTests
//


import XCTest

@testable import moro

@MainActor
final class MoroSceneTests: XCTestCase {
    func testSceneKindsResolveSemanticDefaults() {
        let stream = MoroSceneDescriptor(kind: .stream, presentation: .root)
        XCTAssertEqual(stream.canvas, .content)
        XCTAssertEqual(stream.topBar, .content)
        XCTAssertEqual(stream.surface, .continuous)
        XCTAssertTrue(stream.scrollBehavior.contains(.refreshable))
        XCTAssertTrue(stream.scrollBehavior.contains(.loadsMore))

        let grouped = MoroSceneDescriptor(kind: .grouped)
        XCTAssertEqual(grouped.canvas, .grouped)
        XCTAssertEqual(grouped.topBar, .grouped)
        XCTAssertEqual(grouped.surface, .sectionCard)

        let hero = MoroSceneDescriptor(kind: .hero)
        XCTAssertEqual(hero.canvas, .hero)
        XCTAssertEqual(hero.topBar, .heroOverlay)
        XCTAssertEqual(hero.surface, .hero)
        XCTAssertTrue(hero.scrollBehavior.contains(.collapsesHero))

        let taskSheet = MoroSceneDescriptor(kind: .task, presentation: .sheet)
        XCTAssertEqual(taskSheet.canvas, .task)
        XCTAssertEqual(taskSheet.topBar, .sheet)
        XCTAssertEqual(taskSheet.surface, .input)
    }

    func testLegacyPageScaffoldPreservesCurrentGroupedAppearance() {
        let descriptor = MoroSceneDescriptor.legacyPageScaffold

        XCTAssertEqual(descriptor.kind, .stream)
        XCTAssertEqual(descriptor.identity, "legacy.page-scaffold")
        XCTAssertEqual(descriptor.canvas, .grouped)
        XCTAssertEqual(descriptor.topBar, .grouped)
    }

    func testMainTabsDeclareRootSceneSemantics() {
        let expected: [(MainTab, String, MoroSceneKind, MoroContentSurfaceRole)] = [
            (.home, "root.home", .stream, .continuous),
            (.explore, "root.explore", .discovery, .continuous),
            (.inbox, "root.inbox", .stream, .continuous),
            (.me, "root.me", .hero, .hero),
        ]

        for (tab, identity, kind, surface) in expected {
            let descriptor = tab.rootSceneDescriptor
            XCTAssertEqual(descriptor.identity, identity)
            XCTAssertEqual(descriptor.kind, kind)
            XCTAssertEqual(descriptor.surface, surface)
        }

        XCTAssertEqual(MainTab.home.rootSceneDescriptor.canvas, .content)
        XCTAssertEqual(MainTab.explore.rootSceneDescriptor.canvas, .content)
        XCTAssertEqual(MainTab.inbox.rootSceneDescriptor.canvas, .content)
        XCTAssertEqual(MainTab.me.rootSceneDescriptor.canvas, .hero)
        XCTAssertTrue(MainTab.home.rootSceneDescriptor.scrollBehavior.contains(.reportsElevation))
        XCTAssertTrue(MainTab.inbox.rootSceneDescriptor.scrollBehavior.contains(.refreshable))
        XCTAssertTrue(MainTab.me.rootSceneDescriptor.scrollBehavior.contains(.collapsesHero))
    }

    func testRoutesDeclareSceneSemantics() throws {
        XCTAssertEqual(Route.bookmarks.sceneDescriptor.kind, .stream)
        XCTAssertEqual(
            Route.profileConnections(accountID: "account", kind: .followers).sceneDescriptor.kind,
            .stream
        )
        XCTAssertEqual(Route.search(query: nil).sceneDescriptor.kind, .discovery)
        XCTAssertEqual(Route.editProfile.sceneDescriptor.kind, .task)

        let mediaURL = try XCTUnwrap(URL(string: "https://example.com/media.jpg"))
        let mediaScene = Route.mediaPreview(url: mediaURL).sceneDescriptor
        XCTAssertEqual(mediaScene.presentation, .immersive)
        XCTAssertEqual(mediaScene.canvas, .immersive)
        XCTAssertEqual(mediaScene.topBar, .hidden)
        XCTAssertEqual(mediaScene.surface, .immersive)
    }
}
