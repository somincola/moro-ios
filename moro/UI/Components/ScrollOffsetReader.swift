//
//  ScrollOffsetReader.swift
//  moro
//
//  Utilities for tracking scroll offset and direction.
//

import SwiftUI
import Combine

// MARK: - Scroll Offset Preference Key

struct ScrollOffsetPreferenceKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

// MARK: - Scroll State Manager

@MainActor
final class ScrollStateManager: ObservableObject {
    // Avoid synthesized isolated teardown on the iOS 26.0–26.2 concurrency runtime.
    nonisolated deinit {}

    /// Current header visibility (0 = hidden, 1 = visible)
    @Published var headerVisibility: CGFloat = 1
    
    /// Current tab bar visibility (0 = hidden, 1 = visible)
    @Published var tabBarVisibility: CGFloat = 1
    
    private var lastOffset: CGFloat = 0
    private var velocity: CGFloat = 0
    private var isFirstUpdate = true
    
    /// Minimum scroll delta to trigger hide/show
    private let minDelta: CGFloat = 3
    
    /// Velocity multiplier for faster response
    private let velocityMultiplier: CGFloat = 0.015
    
    /// Minimum offset before hiding starts (avoid hiding at top)
    private let minimumOffsetToHide: CGFloat = 100
    
    func updateScroll(offset: CGFloat) {
        // Skip first update to establish baseline
        if isFirstUpdate {
            lastOffset = offset
            isFirstUpdate = false
            return
        }
        
        let delta = offset - lastOffset
        lastOffset = offset
        
        // Ignore tiny movements
        guard abs(delta) > 0.5 else { return }
        
        // At top of content - always show bars
        if offset < minimumOffsetToHide {
            if headerVisibility < 1 {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                    headerVisibility = 1
                    tabBarVisibility = 1
                }
            }
            return
        }
        
        // Calculate target visibility
        var targetVisibility = headerVisibility
        
        if delta > minDelta {
            // Scrolling content UP (loading more below) → HIDE bars
            let change = delta * velocityMultiplier
            targetVisibility = max(0, headerVisibility - change)
        } else if delta < -minDelta {
            // Scrolling content DOWN (viewing earlier) → SHOW bars
            let change = abs(delta) * velocityMultiplier
            targetVisibility = min(1, headerVisibility + change)
        }
        
        // Apply immediately for responsive feel
        headerVisibility = targetVisibility
        tabBarVisibility = targetVisibility
    }
    
    /// Called when scroll decelerates or stops
    func snapToNearestState() {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.9)) {
            if headerVisibility > 0.5 {
                headerVisibility = 1
                tabBarVisibility = 1
            } else {
                headerVisibility = 0
                tabBarVisibility = 0
            }
        }
    }
    
    /// Reset state
    func reset() {
        isFirstUpdate = true
        lastOffset = 0
        headerVisibility = 1
        tabBarVisibility = 1
    }
    
    /// Force show bars
    func showBars() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            headerVisibility = 1
            tabBarVisibility = 1
        }
    }
    
    /// Force hide bars
    func hideBars() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
            headerVisibility = 0
            tabBarVisibility = 0
        }
    }
}

// MARK: - Scroll Tracking Modifier

struct ScrollOffsetModifier: ViewModifier {
    let coordinateSpace: String
    let onOffsetChange: (CGFloat) -> Void
    
    func body(content: Content) -> some View {
        content
            .background(
                GeometryReader { proxy in
                    Color.clear
                        .preference(
                            key: ScrollOffsetPreferenceKey.self,
                            value: -proxy.frame(in: .named(coordinateSpace)).minY
                        )
                }
            )
            .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                onOffsetChange(offset)
            }
    }
}

extension View {
    func trackScrollOffset(in coordinateSpace: String, onOffsetChange: @escaping (CGFloat) -> Void) -> some View {
        modifier(ScrollOffsetModifier(coordinateSpace: coordinateSpace, onOffsetChange: onOffsetChange))
    }
}

