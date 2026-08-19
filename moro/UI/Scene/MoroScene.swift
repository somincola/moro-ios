//
//  MoroScene.swift
//  moro
//
//  Semantic page contracts shared by SwiftUI content and the UIKit app shell.
//

import SwiftUI

enum MoroSceneKind: String, CaseIterable, Hashable, Sendable {
    case stream
    case discovery
    case detail
    case grouped
    case hero
    case task
}

enum MoroPageCanvasRole: String, CaseIterable, Hashable, Sendable {
    case content
    case grouped
    case hero
    case task
    case immersive

    func backgroundColor(in theme: MoroTheme) -> Color {
        switch self {
        case .content, .hero:
            return theme.colors.surfaceBase
        case .grouped, .task:
            return theme.colors.groupedBackground
        case .immersive:
            return theme.colors.immersiveBackground
        }
    }

    var defaultTopBarRole: MoroTopBarRole {
        switch self {
        case .content:
            return .content
        case .grouped, .task:
            return .grouped
        case .hero:
            return .heroOverlay
        case .immersive:
            return .hidden
        }
    }
}

enum MoroTopBarRole: String, CaseIterable, Hashable, Sendable {
    case content
    case grouped
    case heroOverlay
    case sheet
    case hidden

    func backgroundColor(in theme: MoroTheme) -> Color {
        switch self {
        case .content, .sheet:
            return theme.colors.surfaceBase
        case .grouped:
            return theme.colors.groupedBackground
        case .heroOverlay, .hidden:
            return .clear
        }
    }

    func foregroundColor(in theme: MoroTheme) -> Color {
        switch self {
        case .heroOverlay:
            return .white
        case .content, .grouped, .sheet, .hidden:
            return theme.colors.textPrimary
        }
    }

    func secondaryForegroundColor(in theme: MoroTheme) -> Color {
        switch self {
        case .heroOverlay:
            return .white.opacity(0.78)
        case .content, .grouped, .sheet, .hidden:
            return theme.colors.textSecondary
        }
    }

    var showsDivider: Bool {
        switch self {
        case .content, .grouped, .sheet:
            return true
        case .heroOverlay, .hidden:
            return false
        }
    }
}

enum MoroContentSurfaceRole: String, CaseIterable, Hashable, Sendable {
    case continuous
    case sectionCard
    case objectCard
    case input
    case hero
    case immersive
}

enum MoroPresentationRole: String, CaseIterable, Hashable, Sendable {
    case root
    case push
    case sheet
    case fullScreen
    case immersive
}

struct MoroScrollBehavior: OptionSet, Hashable, Sendable {
    let rawValue: Int

    static let scrollable = MoroScrollBehavior(rawValue: 1 << 0)
    static let refreshable = MoroScrollBehavior(rawValue: 1 << 1)
    static let loadsMore = MoroScrollBehavior(rawValue: 1 << 2)
    static let reportsElevation = MoroScrollBehavior(rawValue: 1 << 3)
    static let collapsesHero = MoroScrollBehavior(rawValue: 1 << 4)
}

enum MoroSceneContentState: String, CaseIterable, Hashable, Sendable {
    case idle
    case loading
    case loaded
    case empty
    case error
    case refreshing
    case loadingMore
}

enum MoroCornerRadiusToken: CGFloat, CaseIterable, Hashable, Sendable {
    case small = 8
    case medium = 12
    case large = 16
}

struct MoroSceneDescriptor: Hashable, Sendable {
    /// Stable semantic identity for root scenes. This is metadata only: it must not
    /// be applied through SwiftUI `.id`, because doing so would reset retained state.
    let identity: String?
    let kind: MoroSceneKind
    let canvas: MoroPageCanvasRole
    let topBar: MoroTopBarRole
    let surface: MoroContentSurfaceRole
    let presentation: MoroPresentationRole
    let scrollBehavior: MoroScrollBehavior
    let contentState: MoroSceneContentState

    init(
        identity: String? = nil,
        kind: MoroSceneKind,
        presentation: MoroPresentationRole = .push,
        canvas: MoroPageCanvasRole? = nil,
        topBar: MoroTopBarRole? = nil,
        surface: MoroContentSurfaceRole? = nil,
        scrollBehavior: MoroScrollBehavior? = nil,
        contentState: MoroSceneContentState = .idle
    ) {
        let resolvedCanvas = canvas ?? Self.defaultCanvas(for: kind)

        self.identity = identity
        self.kind = kind
        self.canvas = resolvedCanvas
        self.topBar = topBar ?? Self.defaultTopBar(
            for: kind,
            presentation: presentation,
            canvas: resolvedCanvas
        )
        self.surface = surface ?? Self.defaultSurface(for: kind, canvas: resolvedCanvas)
        self.presentation = presentation
        self.scrollBehavior = scrollBehavior ?? Self.defaultScrollBehavior(for: kind)
        self.contentState = contentState
    }

    /// Compatibility contract for pages still hosted by `PageScaffold`.
    /// It intentionally preserves the existing grouped canvas until each page
    /// is migrated to its final Scene descriptor.
    static let legacyPageScaffold = MoroSceneDescriptor(
        identity: "legacy.page-scaffold",
        kind: .stream,
        presentation: .push,
        canvas: .grouped,
        topBar: .grouped,
        surface: .continuous
    )

    private static func defaultCanvas(for kind: MoroSceneKind) -> MoroPageCanvasRole {
        switch kind {
        case .stream, .discovery, .detail:
            return .content
        case .grouped:
            return .grouped
        case .hero:
            return .hero
        case .task:
            return .task
        }
    }

    private static func defaultTopBar(
        for kind: MoroSceneKind,
        presentation: MoroPresentationRole,
        canvas: MoroPageCanvasRole
    ) -> MoroTopBarRole {
        if kind == .task, presentation == .sheet || presentation == .fullScreen {
            return .sheet
        }

        return canvas.defaultTopBarRole
    }

    private static func defaultSurface(
        for kind: MoroSceneKind,
        canvas: MoroPageCanvasRole
    ) -> MoroContentSurfaceRole {
        if canvas == .immersive {
            return .immersive
        }

        switch kind {
        case .stream, .discovery, .detail:
            return .continuous
        case .grouped:
            return .sectionCard
        case .hero:
            return .hero
        case .task:
            return .input
        }
    }

    private static func defaultScrollBehavior(for kind: MoroSceneKind) -> MoroScrollBehavior {
        switch kind {
        case .stream:
            return [.scrollable, .refreshable, .loadsMore, .reportsElevation]
        case .discovery, .grouped, .task:
            return [.scrollable, .reportsElevation]
        case .detail:
            return [.scrollable, .loadsMore, .reportsElevation]
        case .hero:
            return [.scrollable, .reportsElevation, .collapsesHero]
        }
    }
}

private struct MoroSceneDescriptorKey: EnvironmentKey {
    static let defaultValue: MoroSceneDescriptor? = nil
}

extension EnvironmentValues {
    var moroSceneDescriptor: MoroSceneDescriptor? {
        get { self[MoroSceneDescriptorKey.self] }
        set { self[MoroSceneDescriptorKey.self] = newValue }
    }
}

struct MoroSceneHost<Content: View>: View {
    @Environment(\.moroTheme) private var theme

    let descriptor: MoroSceneDescriptor
    private let content: Content

    init(
        descriptor: MoroSceneDescriptor,
        @ViewBuilder content: () -> Content
    ) {
        self.descriptor = descriptor
        self.content = content()
    }

    var body: some View {
        ZStack {
            descriptor.canvas.backgroundColor(in: theme)
                .ignoresSafeArea()

            content
        }
        .environment(\.moroSceneDescriptor, descriptor)
    }
}

extension View {
    func moroScene(_ descriptor: MoroSceneDescriptor) -> some View {
        MoroSceneHost(descriptor: descriptor) {
            self
        }
    }
}
