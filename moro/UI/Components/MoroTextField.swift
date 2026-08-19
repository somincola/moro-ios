//
//  MoroTextField.swift
//  moro
//
//  Styled text field / text area.
//

import SwiftUI

struct MoroTextField: View {
    let placeholder: String
    @Binding var text: String
    var axis: Axis = .vertical

    @Environment(\.moroTheme) private var theme

    var body: some View {
        TextField(placeholder, text: $text, axis: axis == .vertical ? .vertical : .horizontal)
            .font(theme.typography.body)
            .padding(theme.spacing.m)
            .background(theme.colors.surfaceSubtle)
            .cornerRadius(12)
    }
}

#Preview {
    StatefulPreviewWrapper("") { binding in
        MoroTextField(placeholder: "What's on your mind?", text: binding)
            .padding()
    }
}

/// Helper to enable @Binding previews.
struct StatefulPreviewWrapper<Value>: View {
    @State private var value: Value
    private let content: (Binding<Value>) -> AnyView

    init(_ value: Value, content: @escaping (Binding<Value>) -> some View) {
        _value = State(initialValue: value)
        self.content = { binding in AnyView(content(binding)) }
    }

    var body: some View {
        content($value)
    }
}

