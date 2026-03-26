import AppKit
import Foundation
import STTextView
import SwiftUI

/// A SwiftUI wrapper around STTextView with markdown syntax highlighting.
public struct SlideEditorView: NSViewRepresentable {
    @Binding public var text: String
    public var objectId: UUID
    public var font: NSFont
    public var textColor: NSColor
    public var backgroundColor: NSColor
    public var insertionPointColor: NSColor

    public init(
        text: Binding<String>,
        objectId: UUID = UUID(),
        font: NSFont = .monospacedSystemFont(ofSize: 14, weight: .regular),
        textColor: NSColor = .textColor,
        backgroundColor: NSColor = .textBackgroundColor,
        insertionPointColor: NSColor = .textColor
    ) {
        self._text = text
        self.objectId = objectId
        self.font = font
        self.textColor = textColor
        self.backgroundColor = backgroundColor
        self.insertionPointColor = insertionPointColor
    }

    public func makeCoordinator() -> Coordinator {
        Coordinator(parent: self)
    }

    public func makeNSView(context: Context) -> NSScrollView {
        let scrollView = STTextView.scrollableTextView()
        guard let textView = scrollView.documentView as? STTextView else { return scrollView }

        // Replace the document view with our subclass
        let slideTextView = SlideTextView()
        slideTextView.font = font
        slideTextView.textColor = textColor
        slideTextView.backgroundColor = backgroundColor
        slideTextView.insertionPointColor = insertionPointColor
        slideTextView.isEditable = true
        slideTextView.isSelectable = true
        slideTextView.isHorizontallyResizable = false
        slideTextView.allowsUndo = true
        slideTextView.textDelegate = context.coordinator

        // Set initial text
        context.coordinator.textView = slideTextView
        context.coordinator.isInternalUpdate = true
        slideTextView.text = text
        context.coordinator.isInternalUpdate = false
        context.coordinator.applyHighlighting()

        // Replace document view
        scrollView.documentView = slideTextView

        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.drawsBackground = true
        scrollView.backgroundColor = backgroundColor

        return scrollView
    }

    public func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? SlideTextView else { return }
        let current = textView.text ?? ""
        if current != text {
            context.coordinator.isInternalUpdate = true
            let savedSelection = textView.selectedRange()
            textView.text = text
            if savedSelection.location != NSNotFound {
                textView.textSelection = savedSelection
            }
            context.coordinator.isInternalUpdate = false
            context.coordinator.applyHighlighting()
        }
    }

    // MARK: - Coordinator

    public final class Coordinator: NSObject, STTextViewDelegate {
        var parent: SlideEditorView
        weak var textView: SlideTextView?
        var isInternalUpdate = false
        private var findObservers: [NSObjectProtocol] = []
        private var lastFindLocation: Int = 0
        private var lastFindQuery: String = ""

        init(parent: SlideEditorView) {
            self.parent = parent
            super.init()
            setupFindObservers()
        }

        deinit {
            findObservers.forEach { NotificationCenter.default.removeObserver($0) }
        }

        // MARK: - Find Support

        private func setupFindObservers() {
            // Use raw strings since notification names are defined in AppFeature module
            let nextObs = NotificationCenter.default.addObserver(
                forName: Notification.Name("WebViewFindNext"),
                object: nil, queue: .main
            ) { [weak self] note in
                self?.handleFind(note: note, backwards: false)
            }
            let prevObs = NotificationCenter.default.addObserver(
                forName: Notification.Name("WebViewFindPrevious"),
                object: nil, queue: .main
            ) { [weak self] note in
                self?.handleFind(note: note, backwards: true)
            }
            findObservers = [nextObs, prevObs]
        }

        private func handleFind(note: Notification, backwards: Bool) {
            guard let noteObjectId = note.userInfo?["objectId"] as? UUID,
                  noteObjectId == parent.objectId,
                  let textView = textView else { return }

            let query = (note.userInfo?["query"] as? String) ?? ""

            // Empty query → clear search state
            if query.isEmpty {
                lastFindLocation = 0
                lastFindQuery = ""
                textView.textSelection = NSRange(location: 0, length: 0)
                return
            }

            let text = textView.text ?? ""
            let nsText = text as NSString
            guard nsText.length > 0 else { return }

            // Reset position if query changed
            if query != lastFindQuery {
                lastFindQuery = query
                lastFindLocation = 0
            }

            let options: NSString.CompareOptions = backwards
                ? [.caseInsensitive, .backwards]
                : [.caseInsensitive]

            let searchRange: NSRange
            if backwards {
                searchRange = NSRange(location: 0, length: max(lastFindLocation, 0))
            } else {
                let start = min(lastFindLocation, nsText.length)
                searchRange = NSRange(location: start, length: nsText.length - start)
            }

            var foundRange = nsText.range(of: query, options: options, range: searchRange)

            // Wrap around if not found
            if foundRange.location == NSNotFound {
                let wrapRange = NSRange(location: 0, length: nsText.length)
                foundRange = nsText.range(of: query, options: options, range: wrapRange)
            }

            if foundRange.location != NSNotFound {
                textView.textSelection = foundRange
                textView.scrollRangeToVisible(foundRange)
                lastFindLocation = backwards
                    ? foundRange.location
                    : foundRange.location + foundRange.length
            }
        }

        public func textViewDidChangeText(_ notification: Notification) {
            guard !isInternalUpdate, let textView = textView else { return }
            parent.text = textView.text ?? ""
            applyHighlighting()
        }

        // MARK: - Markdown Highlighting

        func applyHighlighting() {
            guard let textView = textView else { return }
            let text = textView.text ?? ""
            let nsText = text as NSString
            let fullRange = NSRange(location: 0, length: nsText.length)
            guard fullRange.length > 0 else { return }

            let paragraph = NSMutableParagraphStyle()
            paragraph.lineSpacing = 4

            let baseAttrs: [NSAttributedString.Key: Any] = [
                .foregroundColor: parent.textColor,
                .font: parent.font,
                .paragraphStyle: paragraph,
            ]

            textView.setAttributes(baseAttrs, range: fullRange)

            // Process line by line
            nsText.enumerateSubstrings(
                in: fullRange,
                options: [.byLines, .substringNotRequired]
            ) { _, range, _, _ in
                let line = nsText.substring(with: range)
                self.styleMarkdownLine(line, at: range, in: textView)
            }
        }

        // MARK: - Line Styling

        private func styleMarkdownLine(_ line: String, at lineRange: NSRange, in textView: STTextView) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            // Headings
            if trimmed.hasPrefix("# ") {
                let headingFont = NSFont.systemFont(ofSize: parent.font.pointSize * 1.6, weight: .bold)
                textView.addAttributes([.font: headingFont], range: lineRange)
                return
            }
            if trimmed.hasPrefix("## ") {
                let headingFont = NSFont.systemFont(ofSize: parent.font.pointSize * 1.35, weight: .bold)
                textView.addAttributes([.font: headingFont], range: lineRange)
                return
            }
            if trimmed.hasPrefix("### ") {
                let headingFont = NSFont.systemFont(ofSize: parent.font.pointSize * 1.15, weight: .semibold)
                textView.addAttributes([.font: headingFont], range: lineRange)
                return
            }

            // Blockquotes
            if trimmed.hasPrefix("> ") {
                textView.addAttributes([
                    .foregroundColor: NSColor.secondaryLabelColor,
                    .font: NSFont.systemFont(ofSize: parent.font.pointSize, weight: .regular).withTraits(.italic),
                ], range: lineRange)
                return
            }

            // Checkboxes
            if trimmed.hasPrefix("- [x] ") || trimmed.hasPrefix("- [X] ") {
                textView.addAttributes([
                    .foregroundColor: NSColor.tertiaryLabelColor,
                    .strikethroughStyle: NSUnderlineStyle.single.rawValue,
                ], range: lineRange)
            }

            // Lists
            if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") {
                let bulletEnd = (line as NSString).range(of: trimmed.hasPrefix("- ") ? "- " : "* ")
                if bulletEnd.location != NSNotFound {
                    let absRange = NSRange(location: lineRange.location + bulletEnd.location, length: bulletEnd.length)
                    textView.addAttributes([.foregroundColor: NSColor.secondaryLabelColor], range: absRange)
                }
            }

            // Inline patterns within the line
            applyInlinePatterns(line, lineRange: lineRange, in: textView)
        }

        private func applyInlinePatterns(_ line: String, lineRange: NSRange, in textView: STTextView) {
            // Inline code: `text`
            applyInlinePattern(
                #"`([^`]+)`"#,
                in: line, lineRange: lineRange, in: textView,
                attrs: [
                    .font: NSFont.monospacedSystemFont(ofSize: parent.font.pointSize * 0.9, weight: .regular),
                    .foregroundColor: NSColor.systemPink,
                    .backgroundColor: NSColor.quaternaryLabelColor,
                ]
            )

            // Bold: **text** or __text__
            applyInlinePattern(
                #"\*\*(.+?)\*\*|__(.+?)__"#,
                in: line, lineRange: lineRange, in: textView,
                attrs: [.font: NSFont.systemFont(ofSize: parent.font.pointSize, weight: .bold)]
            )

            // Italic: *text* or _text_ (but not ** or __)
            applyInlinePattern(
                #"(?<!\*)\*(?!\*)(.+?)(?<!\*)\*(?!\*)|(?<!_)_(?!_)(.+?)(?<!_)_(?!_)"#,
                in: line, lineRange: lineRange, in: textView,
                attrs: [.font: parent.font.withTraits(.italic)]
            )

            // Markdown links: [text](url)
            applyInlinePattern(
                #"\[([^\]]+)\]\(([^)]+)\)"#,
                in: line, lineRange: lineRange, in: textView,
                attrs: [
                    .foregroundColor: NSColor.linkColor,
                    .underlineStyle: NSUnderlineStyle.single.rawValue,
                ]
            )
        }

        private func applyInlinePattern(
            _ pattern: String,
            in line: String,
            lineRange: NSRange,
            in textView: STTextView,
            attrs: [NSAttributedString.Key: Any]
        ) {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { return }
            let lineNSRange = NSRange(location: 0, length: (line as NSString).length)
            let matches = regex.matches(in: line, range: lineNSRange)
            for match in matches {
                let absoluteRange = NSRange(
                    location: lineRange.location + match.range.location,
                    length: match.range.length
                )
                textView.addAttributes(attrs, range: absoluteRange)
            }
        }
    }
}

// MARK: - Font Helpers

private extension NSFont {
    func withTraits(_ traits: NSFontDescriptor.SymbolicTraits) -> NSFont {
        let descriptor = fontDescriptor.withSymbolicTraits(fontDescriptor.symbolicTraits.union(traits))
        return NSFont(descriptor: descriptor, size: pointSize) ?? self
    }
}
