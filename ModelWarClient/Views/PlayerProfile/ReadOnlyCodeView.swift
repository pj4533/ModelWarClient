import AppKit
import SwiftUI

struct ReadOnlyCodeView: NSViewRepresentable {
    let code: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = true
        textView.font = NSFont.monospacedSystemFont(ofSize: 11, weight: .regular)
        textView.backgroundColor = NSColor.textBackgroundColor.withAlphaComponent(0.5)
        textView.textContainerInset = NSSize(width: 8, height: 6)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainer?.widthTracksTextView = true

        scrollView.documentView = textView

        applyHighlightedCode(to: textView)

        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView else { return }
        applyHighlightedCode(to: textView)
    }

    private func applyHighlightedCode(to textView: NSTextView) {
        guard let textStorage = textView.textStorage else { return }
        textStorage.beginEditing()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: textStorage.length), with: code)
        RedcodeSyntaxHighlighter.highlight(textStorage)
        textStorage.endEditing()
    }
}
