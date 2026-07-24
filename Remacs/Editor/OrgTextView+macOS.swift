//
//  OrgTextView+macOS.swift
//  Remacs
//

#if os(macOS)
import AppKit
import SwiftUI

final class OrgNSTextView: NSTextView {
    var onToggleFold: ((Int) -> Void)?
    var onApplyEmphasis: ((OrgEmphasis) -> Void)?
    var onHeadlineReturn: (() -> Bool)?

    override func insertNewline(_ sender: Any?) {
        if selectedRange().length == 0, onHeadlineReturn?() == true {
            return
        }
        super.insertNewline(sender)
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, let headlineStart = headlineStarCharacterIndex(for: event) {
            onToggleFold?(headlineStart)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        if let emphasis = OrgEmphasis(commandKeyEvent: event) {
            onApplyEmphasis?(emphasis)
            return
        }

        let isPlainTab = event.keyCode == 48 && event.modifierFlags.intersection([.shift, .command, .option, .control]).isEmpty
        if isPlainTab,
           let textStorage = textStorage as? OrgTextStorage,
           let headline = textStorage.headline(atCharacterIndex: selectedRange().location),
           headline.canFold {
            onToggleFold?(headline.lineStart)
            return
        }
        super.keyDown(with: event)
    }

    private func headlineStarCharacterIndex(for event: NSEvent) -> Int? {
        guard let layoutManager, let textContainer, let textStorage = textStorage as? OrgTextStorage else { return nil }
        let point = convert(event.locationInWindow, from: nil)
        let containerPoint = NSPoint(x: point.x - textContainerOrigin.x, y: point.y - textContainerOrigin.y)
        let glyphIndex = layoutManager.glyphIndex(for: containerPoint, in: textContainer)
        guard glyphIndex < layoutManager.numberOfGlyphs else { return nil }
        let charIndex = layoutManager.characterIndexForGlyph(at: glyphIndex)
        guard let headline = textStorage.headline(atCharacterIndex: charIndex),
              charIndex < headline.lineStart + headline.level else { return nil }
        return headline.lineStart
    }
}

private extension OrgEmphasis {
    /// Maps the emphasis keyboard shortcuts (Command-B/I/_/=) to their marker. Command-_
    /// arrives as Shift lowering "-" to "_", so charactersIgnoringModifiers already reflects it.
    init?(commandKeyEvent event: NSEvent) {
        guard event.modifierFlags.contains(.command),
              !event.modifierFlags.contains(.option),
              !event.modifierFlags.contains(.control) else { return nil }
        switch event.charactersIgnoringModifiers {
        case "b": self = .bold
        case "i": self = .italic
        case "_": self = .underline
        case "=": self = .code
        default: return nil
        }
    }
}

struct OrgTextView: NSViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeNSView(context: Context) -> NSScrollView {
        let textStorage = OrgTextStorage()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)

        let layoutManager = NSLayoutManager()
        layoutManager.delegate = context.coordinator.foldingDelegate
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(containerSize: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = OrgNSTextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.isRichText = false
        textView.allowsUndo = true
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isContinuousSpellCheckingEnabled = false
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.font = PlatformFont.orgBody
        textView.onToggleFold = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleFold(atCharacterIndex: index)
        }
        textView.onApplyEmphasis = { [weak coordinator = context.coordinator] emphasis in
            coordinator?.applyEmphasis(emphasis)
        }
        textView.onHeadlineReturn = { [weak coordinator = context.coordinator] in
            coordinator?.applyHeadlineReturn() ?? false
        }

        let scrollView = NSScrollView()
        scrollView.documentView = textView
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false

        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.updateExternalText(text)
    }

    final class Coordinator: NSObject, NSTextViewDelegate {
        var text: Binding<String>
        weak var textView: OrgNSTextView?
        weak var textStorage: OrgTextStorage?
        let foldingDelegate = OrgFoldingLayoutManagerDelegate()

        init(text: Binding<String>) {
            self.text = text
        }

        func textDidChange(_ notification: Notification) {
            guard let textView else { return }
            text.wrappedValue = textView.string
            // The syntax highlighter restyles the whole document on every keystroke
            // (see OrgTextStorage.highlight), which can leave AppKit's own "keep the
            // caret visible" scrolling out of sync with the just-grown layout. Reassert
            // it explicitly so typing past the bottom of the window keeps scrolling.
            textView.scrollRangeToVisible(textView.selectedRange())
        }

        func updateExternalText(_ newValue: String) {
            guard let textView, textView.string != newValue else { return }
            let selectedRanges = textView.selectedRanges
            let length = (newValue as NSString).length
            textView.string = newValue
            textView.selectedRanges = selectedRanges.map { value in
                var r = value.rangeValue
                r.location = min(r.location, length)
                r.length = min(r.length, length - r.location)
                return NSValue(range: r)
            }
        }

        func toggleFold(atCharacterIndex index: Int) {
            guard let textStorage, let headline = textStorage.headline(atCharacterIndex: index) else { return }
            textStorage.toggleFold(for: headline)
        }

        func applyEmphasis(_ emphasis: OrgEmphasis) {
            guard let textView, let textStorage else { return }
            let text = textStorage.string as NSString
            let selected = textView.selectedRange()
            let range = OrgEmphasisFormatting.targetRange(selectedRange: selected, in: text, wordRangeProvider: {
                let proposed = NSRange(location: selected.location, length: 0)
                let word = textView.selectionRange(forProposedRange: proposed, granularity: .selectByWord)
                return word.length > 0 ? word : nil
            })

            let (replaceRange, replacement, newSelection) = OrgEmphasisFormatting.toggle(range, in: text, with: emphasis)
            guard textView.shouldChangeText(in: replaceRange, replacementString: replacement) else { return }
            textStorage.replaceCharacters(in: replaceRange, with: replacement)
            textView.didChangeText()
            textView.setSelectedRange(newSelection)
        }

        /// Returns true if Return was handled specially (starting or clearing a heading),
        /// false if the caller should fall back to inserting a plain newline.
        func applyHeadlineReturn() -> Bool {
            guard let textView, let textStorage else { return false }
            let text = textStorage.string as NSString
            let cursorLocation = textView.selectedRange().location
            let lookupIndex = cursorLocation < text.length ? cursorLocation : max(cursorLocation - 1, 0)
            guard let action = OrgHeadlineReturn.action(
                headline: textStorage.headline(atCharacterIndex: lookupIndex),
                cursorLocation: cursorLocation,
                text: text
            ) else { return false }

            guard textView.shouldChangeText(in: action.replaceRange, replacementString: action.replacement) else { return false }
            textStorage.replaceCharacters(in: action.replaceRange, with: action.replacement)
            textView.didChangeText()
            textView.setSelectedRange(NSRange(location: action.newCursorLocation, length: 0))
            return true
        }
    }
}
#endif
