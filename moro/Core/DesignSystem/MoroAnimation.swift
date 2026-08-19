//
//  MoroAnimation.swift
//  moro
//
//  Moro Design System - Animation Library
//  Encapsulates AnimationTokens into reusable SwiftUI view modifiers.
//
//  Rules:
//  1. All durations/curves from AnimationTokens.swift
//  2. Style: Light, Simple, Friendly
//

import SwiftUI

// MARK: - Tap Feedback

/// A modifier that scales the view down slightly when pressed.
/// Uses `scale.tapDown` (0.94) and `spring.springFirm`.
struct MoroTapFeedbackModifier: ViewModifier {
    @State private var isPressed = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed ? AnimationTokens.scale.tapDown : 1.0)
            .animation(AnimationTokens.easing.springFirm, value: isPressed)
            .onTapGesture {
                withAnimation(AnimationTokens.easing.springFirm) {
                    isPressed = true
                }
                // Reset after a short delay to simulate a tap
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    withAnimation(AnimationTokens.easing.springFirm) {
                        isPressed = false
                    }
                }
            }
    }
}

// MARK: - Bounce Effect (Like/Action)

/// A modifier that performs a bounce animation when the trigger value changes.
/// Uses `scale.likeBounce` (1.12) or `scale.gentleBounce` (1.06).
struct MoroBounceModifier<T: Equatable>: ViewModifier {
    var trigger: T
    var scale: CGFloat
    
    @State private var isBouncing = false
    
    func body(content: Content) -> some View {
        content
            .scaleEffect(isBouncing ? scale : 1.0)
            .animation(AnimationTokens.easing.springMedium, value: isBouncing)
            .onChange(of: trigger) { _, _ in
                // Trigger bounce
                isBouncing = true
                
                // Reset after delay
                DispatchQueue.main.asyncAfter(deadline: .now() + AnimationTokens.duration.xs) {
                    isBouncing = false
                }
            }
    }
}

// MARK: - Slide & Fade (List Entry)

/// A transition modifier for list items or appearing content.
/// Combines opacity fade with a small vertical slide.
/// Uses `motion.md` (8pt) and `easing.easeOutMD`.
struct MoroSlideFadeModifier: ViewModifier {
    var isVisible: Bool
    var edge: Edge = .bottom
    
    func body(content: Content) -> some View {
        content
            .opacity(isVisible ? 1.0 : AnimationTokens.opacity.listStart)
            .offset(y: isVisible ? 0 : (edge == .bottom ? AnimationTokens.motion.md : -AnimationTokens.motion.md))
            .animation(AnimationTokens.easing.easeOutMD, value: isVisible)
    }
}

// MARK: - Modal Transition

/// A transition modifier for bottom sheets or modal dialogs.
/// Uses `motion.lg` (12pt) and `easing.easeOutLG`.
struct MoroModalTransitionModifier: ViewModifier {
    var isPresented: Bool
    
    func body(content: Content) -> some View {
        content
            .offset(y: isPresented ? 0 : AnimationTokens.motion.lg)
            .opacity(isPresented ? 1.0 : 0.0)
            .animation(AnimationTokens.easing.easeOutLG, value: isPresented)
    }
}

// MARK: - View Extensions

public extension View {
    
    /// Adds a gentle scale-down animation on tap.
    /// Ideal for buttons, list rows, and interactive cards.
    ///
    /// Usage:
    /// ```swift
    /// Button("Submit") { ... }
    ///     .moroTapFeedback()
    /// ```
    func moroTapFeedback() -> some View {
        modifier(MoroTapFeedbackModifier())
    }
    
    /// Adds a bouncy scale animation when the trigger value changes.
    /// Ideal for Like buttons, toggle states, or attention-grabbing icons.
    ///
    /// - Parameters:
    ///   - trigger: The value that triggers the animation when changed.
    ///   - isIntense: If true, uses `scale.likeBounce` (1.12). If false, uses `scale.gentleBounce` (1.06).
    ///
    /// Usage:
    /// ```swift
    /// Image(systemName: "heart.fill")
    ///     .moroBounce(trigger: isLiked, isIntense: true)
    /// ```
    func moroBounce<T: Equatable>(trigger: T, isIntense: Bool = true) -> some View {
        modifier(MoroBounceModifier(
            trigger: trigger,
            scale: isIntense ? AnimationTokens.scale.likeBounce : AnimationTokens.scale.gentleBounce
        ))
    }
    
    /// Applies a standard "Slide & Fade" entry animation.
    /// Ideal for list items loading, new posts appearing, or content switching.
    ///
    /// - Parameter isVisible: Controls the visibility state.
    ///
    /// Usage:
    /// ```swift
    /// Text("New Post")
    ///     .moroSlideFade(isVisible: showPost)
    /// ```
    func moroSlideFade(isVisible: Bool) -> some View {
        modifier(MoroSlideFadeModifier(isVisible: isVisible))
    }
    
    /// Applies a standard transition for modals or bottom sheets.
    ///
    /// - Parameter isPresented: Controls the presentation state.
    ///
    /// Usage:
    /// ```swift
    /// if showModal {
    ///     ModalView()
    ///         .moroModalTransition(isPresented: showModal)
    /// }
    /// ```
    func moroModalTransition(isPresented: Bool) -> some View {
        modifier(MoroModalTransitionModifier(isPresented: isPresented))
    }
}

public extension AnyTransition {
    /// Standard Moro transition for insertion/removal from view hierarchy.
    /// Combines opacity and a small vertical move.
    ///
    /// Usage:
    /// ```swift
    /// if showDetails {
    ///     DetailsView()
    ///         .transition(.moroStandard)
    /// }
    /// ```
    static var moroStandard: AnyTransition {
        .opacity.combined(with: .move(edge: .bottom).animation(AnimationTokens.easing.easeOutMD))
    }
}

// MARK: - Previews & Examples

#Preview("Moro Animations") {
    VStack(spacing: 40) {
        
        // Example 1: Tap Feedback
        VStack {
            Text("Tap Feedback")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            HStack(spacing: 20) {
                Text("Tap Me")
                    .padding()
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(8)
                    .moroTapFeedback()
                
                Image(systemName: "star.fill")
                    .font(.largeTitle)
                    .foregroundStyle(.yellow)
                    .moroTapFeedback()
            }
        }
        
        // Example 2: Bounce (Like)
        VStack {
            Text("Bounce Effect")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            BounceExampleView()
        }
        
        // Example 3: Slide Fade
        VStack {
            Text("Slide Fade Entry")
                .font(.caption)
                .foregroundStyle(.secondary)
            
            SlideFadeExampleView()
        }
    }
}

// Helper views for preview
struct BounceExampleView: View {
    @State private var count = 0
    
    var body: some View {
        Button(action: { count += 1 }) {
            HStack {
                Image(systemName: "heart.fill")
                    .font(.title)
                    .foregroundStyle(.red)
                    .moroBounce(trigger: count, isIntense: true)
                
                Text("Like (\(count))")
            }
        }
        .buttonStyle(.plain)
    }
}

struct SlideFadeExampleView: View {
    @State private var show = false
    
    var body: some View {
        VStack {
            Button("Toggle") { show.toggle() }
            
            if show {
                Text("Hello World")
                    .padding()
                    .background(Color.green.opacity(0.2))
                    .cornerRadius(8)
                    .transition(.moroStandard)
            }
        }
        .animation(AnimationTokens.easing.easeOutMD, value: show)
    }
}
