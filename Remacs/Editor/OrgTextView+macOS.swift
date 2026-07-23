//
//  OrgTextView+macOS.swift
//  Remacs
//

#if os(macOS)
import AppKit
import SwiftUI

final class OrgNSTextView: NSTextView {
    var onToggleFold: ((Int) -> Void)?

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 1, let headlineStart = headlineStarCharacterIndex(for: event) {
            onToggleFold?(headlineStart)
            return
        }
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
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
        textView.autoresizingMask = [NSView.AutoresizingMask.width]
        textView.font = PlatformFont.orgBody
        textView.onToggleFold = { [weak coordinator = context.coordinator] index in
            coordinator?.toggleFold(atCharacterIndex: index)
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
    }
}
#endif
