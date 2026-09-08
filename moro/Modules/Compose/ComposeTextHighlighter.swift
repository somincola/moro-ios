import UIKit

/// Presentation only: the composer, drafts, and publishing API still use plain text.
enum ComposeTextHighlighter {
    private static let tokenExpression = try! NSRegularExpression(
        pattern: #"(?<![\p{L}\p{M}\p{N}_@#./:\-])(?:@[A-Za-z0-9_]+(?:[.\-][A-Za-z0-9_]+)*(?:@[\p{L}\p{N}]+(?:[.\-][\p{L}\p{N}]+)*)?(?![\p{L}\p{M}\p{N}_@\-])|#(?=[\p{L}\p{M}\p{N}_]*[\p{L}_])[\p{L}\p{N}_][\p{L}\p{M}\p{N}_]*)"#
    )
    private static let urlExpression = try! NSRegularExpression(
        pattern: #"(?:[a-z][a-z0-9+.\-]*://|www\.)[^\s]+"#,
        options: .caseInsensitive
    )

    static func ranges(in text: String) -> [NSRange] {
        let fullRange = NSRange(location: 0, length: text.utf16.count)
        let urls = urlExpression.matches(in: text, range: fullRange).map(\.range)
        return tokenExpression.matches(in: text, range: fullRange).map(\.range).filter { token in
            !urls.contains { NSIntersectionRange($0, token).length > 0 }
        }
    }

    @MainActor
    static func apply(to textView: UITextView, textColor: UIColor, tokenColor: UIColor) {
        // Touching attributes during IME composition can commit or disturb marked text.
        guard textView.markedTextRange == nil else { return }

        let storage = textView.textStorage
        var changes: [(NSRange, UIColor)] = []
        func collectChanges(in range: NSRange, color: UIColor) {
            guard range.length > 0 else { return }
            storage.enumerateAttribute(.foregroundColor, in: range) { value, run, _ in
                if (value as? UIColor) != color { changes.append((run, color)) }
            }
        }

        var start = 0
        for token in ranges(in: storage.string) {
            collectChanges(in: NSRange(location: start, length: token.location - start), color: textColor)
            collectChanges(in: token, color: tokenColor)
            start = NSMaxRange(token)
        }
        collectChanges(in: NSRange(location: start, length: storage.length - start), color: textColor)

        // Attribute-only edits preserve UIKit's selection and text-edit undo history.
        if !changes.isEmpty {
            let undoManager = textView.undoManager
            let wasRegisteringUndo = undoManager?.isUndoRegistrationEnabled == true
            if wasRegisteringUndo { undoManager?.disableUndoRegistration() }
            defer { if wasRegisteringUndo { undoManager?.enableUndoRegistration() } }

            storage.beginEditing()
            for (range, color) in changes {
                storage.addAttribute(.foregroundColor, value: color, range: range)
            }
            storage.endEditing()
        }

        // Selection changes can inherit the preceding token's color. Always start
        // ordinary typing in the body color; valid tokens are recolored after editing.
        if (textView.typingAttributes[.foregroundColor] as? UIColor) != textColor {
            var attributes = textView.typingAttributes
            attributes[.foregroundColor] = textColor
            textView.typingAttributes = attributes
        }
    }
}
