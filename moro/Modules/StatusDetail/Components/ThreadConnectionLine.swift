//
//  ThreadConnectionLine.swift
//  moro
//
//  Animated vertical connection line for thread visualization.
//

import SwiftUI

/// Configuration for which segments of the thread line to draw
struct ThreadLineConfig: Equatable {
    let drawsAbove: Bool
    let drawsBelow: Bool
    
    static let none = ThreadLineConfig(drawsAbove: false, drawsBelow: false)
    static let above = ThreadLineConfig(drawsAbove: true, drawsBelow: false)
    static let below = ThreadLineConfig(drawsAbove: false, drawsBelow: true)
    static let both = ThreadLineConfig(drawsAbove: true, drawsBelow: true)
}

/// Animated vertical thread connection line
struct ThreadConnectionLine: View {
    let config: ThreadLineConfig
    let avatarSize: CGFloat
    let topPadding: CGFloat
    let animate: Bool
    
    @Environment(\.moroTheme) private var theme
    @State private var animationProgress: CGFloat = 0
    
    private let lineWidth: CGFloat = 2
    
    init(
        config: ThreadLineConfig,
        avatarSize: CGFloat = 36,
        topPadding: CGFloat = 12,
        animate: Bool = true
    ) {
        self.config = config
        self.avatarSize = avatarSize
        self.topPadding = topPadding
        self.animate = animate
    }
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = avatarSize / 2
            let avatarTopY = topPadding
            let avatarBottomY = topPadding + avatarSize
            
            Canvas { context, size in
                let linePath = Path { path in
                    // Upper segment (from top to avatar)
                    if config.drawsAbove {
                        path.move(to: CGPoint(x: centerX, y: 0))
                        path.addLine(to: CGPoint(x: centerX, y: avatarTopY))
                    }
                    
                    // Lower segment (from avatar to bottom)
                    if config.drawsBelow {
                        path.move(to: CGPoint(x: centerX, y: avatarBottomY))
                        path.addLine(to: CGPoint(x: centerX, y: size.height))
                    }
                }
                
                if animate {
                    // Animated drawing with trim
                    let animatedPath = linePath.trimmedPath(from: 0, to: animationProgress)
                    context.stroke(
                        animatedPath,
                        with: .color(theme.colors.primary300),
                        lineWidth: lineWidth
                    )
                } else {
                    context.stroke(
                        linePath,
                        with: .color(theme.colors.primary300),
                        lineWidth: lineWidth
                    )
                }
            }
        }
        .onAppear {
            if animate {
                withAnimation(.easeOut(duration: 0.4)) {
                    animationProgress = 1.0
                }
            } else {
                animationProgress = 1.0
            }
        }
    }
}

/// Thread line overlay that can be placed on top of a status row
struct ThreadLineOverlay: View {
    let config: ThreadLineConfig
    let horizontalPadding: CGFloat
    let avatarSize: CGFloat
    let topPadding: CGFloat
    let animate: Bool
    let animationDelay: Double
    
    @Environment(\.moroTheme) private var theme
    @State private var showLine = false
    
    init(
        config: ThreadLineConfig,
        horizontalPadding: CGFloat = MoroLayoutMetrics.contentHorizontalInset,
        avatarSize: CGFloat = 36,
        topPadding: CGFloat = 12,
        animate: Bool = true,
        animationDelay: Double = 0
    ) {
        self.config = config
        self.horizontalPadding = horizontalPadding
        self.avatarSize = avatarSize
        self.topPadding = topPadding
        self.animate = animate
        self.animationDelay = animationDelay
    }
    
    var body: some View {
        GeometryReader { geometry in
            let centerX = horizontalPadding + avatarSize / 2
            let avatarTopY = topPadding
            let avatarBottomY = topPadding + avatarSize
            
            ZStack {
                // Upper segment
                if config.drawsAbove && showLine {
                    Rectangle()
                        .fill(theme.colors.primary300)
                        .frame(width: 2)
                        .frame(height: avatarTopY)
                        .position(x: centerX, y: avatarTopY / 2)
                        .transition(.opacity.combined(with: .scale(scale: 1, anchor: .bottom)))
                }
                
                // Lower segment
                if config.drawsBelow && showLine {
                    let lowerHeight = max(0, geometry.size.height - avatarBottomY)
                    if lowerHeight > 0 {
                        Rectangle()
                            .fill(theme.colors.primary300)
                            .frame(width: 2)
                            .frame(height: lowerHeight)
                            .position(x: centerX, y: avatarBottomY + lowerHeight / 2)
                            .transition(.opacity.combined(with: .scale(scale: 1, anchor: .top)))
                    }
                }
            }
        }
        .onAppear {
            if animate {
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDelay) {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showLine = true
                    }
                }
            } else {
                showLine = true
            }
        }
    }
}

#Preview {
    VStack(spacing: 0) {
        ZStack {
            ThreadLineOverlay(config: .below, animate: true)
            Text("First post (root)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(height: 80)
        .background(Color.gray.opacity(0.1))
        
        ZStack {
            ThreadLineOverlay(config: .both, animate: true, animationDelay: 0.2)
            Text("Middle post (continuation)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(height: 80)
        .background(Color.gray.opacity(0.15))
        
        ZStack {
            ThreadLineOverlay(config: .above, animate: true, animationDelay: 0.4)
            Text("Last post (end)")
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
        }
        .frame(height: 80)
        .background(Color.gray.opacity(0.1))
    }
    .moroTheme(MoroTheme())
}
