//
//  OrgTextView+iOS.swift
//  Remacs
//

#if os(iOS) || os(visionOS)
import UIKit
import SwiftUI

final class OrgUITextView: UITextView {
    /// Returns true if the tab was consumed (i.e. it toggled a fold); if not, a literal
    /// tab character is inserted, matching how a hardware keyboard's Tab key behaves.
    var onToggleFoldAtSelection: (() -> Bool)?
    var onApplyEmphasis: ((OrgEmphasis) -> Void)?

    override var keyCommands: [UIKeyCommand]? {
        [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabCommand)),
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(handleBoldCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(handleItalicCommand)),
            UIKeyCommand(input: "_", modifierFlags: .command, action: #selector(handleUnderlineCommand)),
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(handleCodeCommand))
        ]
    }

    @objc private func handleTabCommand() {
        if onToggleFoldAtSelection?() != true {
            insertText("\t")
        }
    }

    @objc private func handleBoldCommand() { onApplyEmphasis?(.bold) }
    @objc private func handleItalicCommand() { onApplyEmphasis?(.italic) }
    @objc private func handleUnderlineCommand() { onApplyEmphasis?(.underline) }
    @objc private func handleCodeCommand() { onApplyEmphasis?(.code) }
}

struct OrgTextView: UIViewRepresentable {
    @Binding var text: String

    func makeCoordinator() -> Coordinator { Coordinator(text: $text) }

    func makeUIView(context: Context) -> UITextView {
        let textStorage = OrgTextStorage()
        textStorage.replaceCharacters(in: NSRange(location: 0, length: 0), with: text)

        let layoutManager = NSLayoutManager()
        layoutManager.delegate = context.coordinator.foldingDelegate
        textStorage.addLayoutManager(layoutManager)

        let textContainer = NSTextContainer(size: CGSize(width: 0, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        layoutManager.addTextContainer(textContainer)

        let textView = OrgUITextView(frame: .zero, textContainer: textContainer)
        textView.delegate = context.coordinator
        textView.autocorrectionType = .no
        textView.autocapitalizationType = .none
        textView.smartQuotesType = .no
        textView.smartDashesType = .no
        textView.smartInsertDeleteType = .no
        textView.font = PlatformFont.orgBody
        textView.textContainerInset = UIEdgeInsets(top: 8, left: 8, bottom: 8, right: 8)
        textView.backgroundColor = .clear
        textView.alwaysBounceVertical = true
        textView.onToggleFoldAtSelection = { [weak coordinator = context.coordinator] in
            coordinator?.toggleFoldAtSelection() ?? false
        }
        textView.onApplyEmphasis = { [weak coordinator = context.coordinator] emphasis in
            coordinator?.applyEmphasis(emphasis)
        }

        let tap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        tap.delegate = context.coordinator
        textView.addGestureRecognizer(tap)

        context.coordinator.textView = textView
        context.coordinator.textStorage = textStorage
        return textView
    }

    func updateUIView(_ uiView: UITextView, context: Context) {
        context.coordinator.updateExternalText(text)
    }

    final class Coordinator: NSObject, UITextViewDelegate, UIGestureRecognizerDelegate {
        var text: Binding<String>
        weak var textView: UITextView?
        weak var textStorage: OrgTextStorage?
        let foldingDelegate = OrgFoldingLayoutManagerDelegate()

        init(text: Binding<String>) {
            self.text = text
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
        }

        func updateExternalText(_ newValue: String) {
            guard let textView, textView.text != newValue else { return }
            let selectedRange = textView.selectedRange
            textView.text = newValue
            let length = (newValue as NSString).length
            let location = min(selectedRange.location, length)
            textView.selectedRange = NSRange(location: location, length: min(selectedRange.length, length - location))
        }

        func toggleFoldAtSelection() -> Bool {
            guard let textView, let textStorage,
                  let headline = textStorage.headline(atCharacterIndex: textView.selectedRange.location),
                  headline.canFold else { return false }
            textStorage.toggleFold(for: headline)
            return true
        }

        func applyEmphasis(_ emphasis: OrgEmphasis) {
            guard let textView, let textStorage else { return }
            let text = textStorage.string as NSString
            let selected = textView.selectedRange
            let range = OrgEmphasisFormatting.targetRange(selectedRange: selected, in: text, wordRangeProvider: {
                wordRange(in: textView, at: selected.location)
            })

            let (replacement, innerSelection) = OrgEmphasisFormatting.wrap(range, in: text, with: emphasis)
            guard let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return }
            textView.replace(textRange, withText: replacement)

            if let newStart = textView.position(from: textView.beginningOfDocument, offset: innerSelection.location),
               let newEnd = textView.position(from: newStart, offset: innerSelection.length) {
                textView.selectedTextRange = textView.textRange(from: newStart, to: newEnd)
            }
        }

        private func wordRange(in textView: UITextView, at index: Int) -> NSRange? {
            guard let position = textView.position(from: textView.beginningOfDocument, offset: index),
                  let range = textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: UITextDirection(rawValue: UITextStorageDirection.forward.rawValue)) else { return nil }
            let start = textView.offset(from: textView.beginningOfDocument, to: range.start)
            let length = textView.offset(from: range.start, to: range.end)
            return NSRange(location: start, length: length)
        }

        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        @objc func handleTap(_ recognizer: UITapGestureRecognizer) {
            guard let textView, let textStorage else { return }
            let point = recognizer.location(in: textView)
            guard let position = textView.closestPosition(to: point) else { return }
            let charIndex = textView.offset(from: textView.beginningOfDocument, to: position)
            guard let headline = textStorage.headline(atCharacterIndex: charIndex),
                  charIndex < headline.lineStart + headline.level else { return }
            textStorage.toggleFold(for: headline)
        }
    }
}
#endif
