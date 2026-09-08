import Testing
import UIKit
@testable import moro

@MainActor
struct ComposeTextHighlighterTests {
    @Test(arguments: [
        ("@hanna ", ["@hanna"]),
        ("@hanna@remote.example done", ["@hanna@remote.example"]),
        ("Hi @user_name, (@first.last@social.example)!", ["@user_name", "@first.last@social.example"]),
        ("👨‍👩‍👧‍👦 你好，@hanna。 #中文话题 #Swift_UI\n#cafe\u{301}", ["@hanna", "#中文话题", "#Swift_UI", "#cafe\u{301}"]),
        ("#2026年 #_tag #123", ["#2026年", "#_tag"]),
        ("@hanna #SwiftUI", ["@hanna", "#SwiftUI"]),
        ("@hanna@例子.中国 ", ["@hanna@例子.中国"])
    ])
    func recognizesCompleteTokens(_ text: String, _ expected: [String]) {
        let matches = ComposeTextHighlighter.ranges(in: text).map { (text as NSString).substring(with: $0) }
        #expect(matches == expected)
    }

    @Test(arguments: [
        "@ # @@han @han@ @han@@remote ##tag #123",
        "mail@example.com name#tag",
        "https://example.com/@hanna https://example.com/#SwiftUI",
        "https://example.com/?q=(@hanna)&tag=(#SwiftUI)",
        "www.example.com/(#SwiftUI) ftp://example.com/(@hanna)",
        "ordinary text 👋"
    ])
    func ignoresIncompleteTokensEmailsAndURLContents(_ text: String) {
        #expect(ComposeTextHighlighter.ranges(in: text).isEmpty)
    }

    @Test func stylesManualInputAndPreservesPlainTextSelectionAndFont() {
        let text = "👋 @hanna #中文话题 ordinary text"
        let editor = makeEditor(text)
        let selection = (text as NSString).range(of: "ordinary")
        editor.selectedRange = selection
        let font = editor.font

        highlight(editor)

        #expect(editor.text == text)
        #expect(editor.selectedRange == selection)
        expectColor(.systemBlue, in: "@hanna", editor: editor)
        expectColor(.systemBlue, in: "#中文话题", editor: editor)
        expectColor(.label, in: " ordinary text", editor: editor)
        #expect((editor.typingAttributes[.foregroundColor] as? UIColor) == .label)
        editor.textStorage.enumerateAttribute(.font, in: NSRange(location: 0, length: text.utf16.count)) { value, _, _ in
            #expect((value as? UIFont) == font)
        }
        #expect(editor.attributedText.attribute(.link, at: 3, effectiveRange: nil) == nil)
    }

    @Test func candidateInsertionAndFollowingTypingUseIndependentColors() throws {
        let editor = makeEditor("Hello @han")
        let token = try #require(ComposeAutocompleteToken.active(in: editor.text, selection: editor.selectedRange))
        let result = try #require(token.inserting("@hanna@remote.example", into: editor.text, selection: editor.selectedRange))
        editor.text = result.text
        editor.selectedRange = result.selection
        highlight(editor)
        editor.insertText("done")
        highlight(editor)

        #expect(editor.text == "Hello @hanna@remote.example done")
        expectColor(.systemBlue, in: "@hanna@remote.example", editor: editor)
        expectColor(.label, in: " done", editor: editor)
    }

    @Test func editingAndMovingCaretDoesNotLeakTokenColor() {
        let editor = makeEditor("@hanna #SwiftUI ")
        highlight(editor)
        editor.selectedRange = NSRange(location: 6, length: 0)
        highlight(editor)
        editor.insertText(" ordinary")
        highlight(editor)
        #expect(editor.text == "@hanna ordinary #SwiftUI ")
        expectColor(.label, in: " ordinary ", editor: editor)

        editor.selectedRange = NSRange(location: 0, length: 1)
        editor.deleteBackward()
        highlight(editor)
        #expect(editor.text == "hanna ordinary #SwiftUI ")
        expectColor(.label, in: "hanna", editor: editor)
        expectColor(.systemBlue, in: "#SwiftUI", editor: editor)
    }

    @Test func themeChangesRecolorExistingTextWithoutChangingSelection() {
        let editor = makeEditor("@hanna body #SwiftUI")
        highlight(editor)
        let selection = editor.selectedRange
        ComposeTextHighlighter.apply(to: editor, textColor: .white, tokenColor: .cyan)
        expectColor(.cyan, in: "@hanna", editor: editor)
        expectColor(.white, in: " body ", editor: editor)
        #expect(editor.selectedRange == selection)
        #expect((editor.typingAttributes[.foregroundColor] as? UIColor) == .white)
    }

    @Test func markedTextIsUntouchedUntilCompositionCommits() throws {
        let editor = makeEditor("#")
        editor.setMarkedText("中文", selectedRange: NSRange(location: 2, length: 0))
        let markedRange = try #require(editor.markedTextRange)
        let markedText = editor.text(in: markedRange)
        let before = NSAttributedString(attributedString: editor.textStorage)
        let selection = editor.selectedRange
        highlight(editor)
        #expect(editor.textStorage.isEqual(to: before))
        #expect(editor.selectedRange == selection)
        #expect(editor.markedTextRange != nil)
        #expect(editor.text(in: try #require(editor.markedTextRange)) == markedText)

        editor.unmarkText()
        highlight(editor)
        #expect(editor.text == "#中文")
        expectColor(.systemBlue, in: "#中文", editor: editor)
        editor.insertText(" 正文")
        highlight(editor)
        expectColor(.label, in: " 正文", editor: editor)
    }

    @Test(arguments: [false, true])
    func highlightingPreservesNativeTextUndoAndRedo(_ usesHighlighting: Bool) throws {
        // UIKit's native undo operations require an attached, active editor.
        let scene = try #require(UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.first)
        let previousWindow = scene.keyWindow
        let window = UIWindow(windowScene: scene)
        let controller = UIViewController()
        window.rootViewController = controller
        let editor = makeEditor("")
        editor.frame = CGRect(x: 0, y: 0, width: 300, height: 200)
        controller.view.addSubview(editor)
        window.makeKeyAndVisible()
        #expect(editor.becomeFirstResponder())
        defer {
            editor.resignFirstResponder()
            window.isHidden = true
            previousWindow?.makeKey()
        }
        let history = try #require(editor.undoManager)
        history.groupsByEvent = false
        history.beginUndoGrouping()
        editor.insertText("@hanna ")
        history.endUndoGrouping()
        if usesHighlighting { highlight(editor) }
        #expect(history.canUndo)

        history.undo()
        #expect(editor.text.isEmpty)
        if usesHighlighting { highlight(editor) }
        #expect(!history.canUndo)
        #expect(history.canRedo)

        history.redo()
        if usesHighlighting { highlight(editor) }
        #expect(editor.text == "@hanna ")
        if usesHighlighting {
            expectColor(.systemBlue, in: "@hanna", editor: editor)
            expectColor(.label, in: " ", editor: editor)
        }
        #expect(history.isUndoRegistrationEnabled)
    }

    private func makeEditor(_ text: String) -> UITextView {
        let editor = UITextView()
        editor.font = .preferredFont(forTextStyle: .body)
        editor.textColor = .label
        editor.text = text
        editor.selectedRange = NSRange(location: text.utf16.count, length: 0)
        return editor
    }

    private func highlight(_ editor: UITextView) {
        ComposeTextHighlighter.apply(to: editor, textColor: .label, tokenColor: .systemBlue)
    }

    private func expectColor(_ color: UIColor, in substring: String, editor: UITextView, sourceLocation: SourceLocation = #_sourceLocation) {
        let range = (editor.text as NSString).range(of: substring)
        #expect(range.location != NSNotFound, sourceLocation: sourceLocation)
        guard range.location != NSNotFound else { return }
        editor.textStorage.enumerateAttribute(.foregroundColor, in: range) { value, _, _ in
            #expect((value as? UIColor) == color, sourceLocation: sourceLocation)
        }
    }
}
