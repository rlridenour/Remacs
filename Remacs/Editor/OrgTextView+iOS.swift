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
    var onDemoteList: (() -> Bool)?
    var onPromoteList: (() -> Bool)?
    var onDemoteHeadline: (() -> Bool)?
    var onPromoteHeadline: (() -> Bool)?
    var onExpandSnippet: (() -> Bool)?

    override var keyCommands: [UIKeyCommand]? {
        var commands = [
            UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabCommand)),
            UIKeyCommand(input: "\t", modifierFlags: .shift, action: #selector(handlePromoteCommand)),
            UIKeyCommand(input: "b", modifierFlags: .command, action: #selector(handleBoldCommand)),
            UIKeyCommand(input: "i", modifierFlags: .command, action: #selector(handleItalicCommand)),
            UIKeyCommand(input: "u", modifierFlags: .command, action: #selector(handleUnderlineCommand)),
            UIKeyCommand(input: "=", modifierFlags: .command, action: #selector(handleCodeCommand))
        ]

        // Option-Right/Left normally move the caret by word. On a heading line they
        // instead demote/promote it (matching Emacs org-mode's M-right/M-left) -- only
        // claim those key combos while on a heading, so word movement is untouched
        // everywhere else, and promotion still falls back to word movement at the top level.
        if let headline = headlineAtSelection {
            commands.append(UIKeyCommand(input: UIKeyCommand.inputRightArrow, modifierFlags: .alternate, action: #selector(handleDemoteHeadlineCommand)))
            if headline.level > 1 {
                commands.append(UIKeyCommand(input: UIKeyCommand.inputLeftArrow, modifierFlags: .alternate, action: #selector(handlePromoteHeadlineCommand)))
            }
        }

        return commands
    }

    private var headlineAtSelection: OrgHeadline? {
        (textStorage as? OrgTextStorage)?.headline(atCharacterIndex: selectedRange.location)
    }

    @objc private func handleTabCommand() {
        if onExpandSnippet?() == true { return }
        if onToggleFoldAtSelection?() == true { return }
        if onDemoteList?() == true { return }
        insertText("\t")
    }

    @objc private func handlePromoteCommand() {
        _ = onPromoteList?()
    }

    @objc private func handleDemoteHeadlineCommand() { _ = onDemoteHeadline?() }
    @objc private func handlePromoteHeadlineCommand() { _ = onPromoteHeadline?() }

    @objc private func handleBoldCommand() { onApplyEmphasis?(.bold) }
    @objc private func handleItalicCommand() { onApplyEmphasis?(.italic) }
    @objc private func handleUnderlineCommand() { onApplyEmphasis?(.underline) }
    @objc private func handleCodeCommand() { onApplyEmphasis?(.code) }
}

struct OrgTextView: UIViewRepresentable {
    @Binding var text: String
    let controller: OrgTextViewController

    func makeCoordinator() -> Coordinator { Coordinator(text: $text, controller: controller) }

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
        textView.backgroundColor = .orgBackground
        textView.alwaysBounceVertical = true
        textView.onToggleFoldAtSelection = { [weak coordinator = context.coordinator] in
            coordinator?.toggleFoldAtSelection() ?? false
        }
        textView.onApplyEmphasis = { [weak coordinator = context.coordinator] emphasis in
            coordinator?.applyEmphasis(emphasis)
        }
        textView.onDemoteList = { [weak coordinator = context.coordinator] in
            coordinator?.demoteList() ?? false
        }
        textView.onPromoteList = { [weak coordinator = context.coordinator] in
            coordinator?.promoteList() ?? false
        }
        textView.onDemoteHeadline = { [weak coordinator = context.coordinator] in
            coordinator?.demoteHeadline() ?? false
        }
        textView.onPromoteHeadline = { [weak coordinator = context.coordinator] in
            coordinator?.promoteHeadline() ?? false
        }
        textView.onExpandSnippet = { [weak coordinator = context.coordinator] in
            coordinator?.expandSnippet() ?? false
        }
        controller.selectHandler = { [weak textView] range in
            guard let textView else { return }
            textView.selectedRange = range
            textView.scrollRangeToVisible(range)
            textView.becomeFirstResponder()
        }
        controller.replaceHandler = { [weak coordinator = context.coordinator] range, replacement in
            coordinator?.replaceText(in: range, with: replacement) ?? false
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
        let controller: OrgTextViewController
        weak var textView: UITextView?
        weak var textStorage: OrgTextStorage?
        let foldingDelegate = OrgFoldingLayoutManagerDelegate()

        init(text: Binding<String>, controller: OrgTextViewController) {
            self.text = text
            self.controller = controller
        }

        func textViewDidChange(_ textView: UITextView) {
            text.wrappedValue = textView.text
            textView.scrollRangeToVisible(textView.selectedRange)
        }

        func textViewDidChangeSelection(_ textView: UITextView) {
            controller.updateSelection(textView.selectedRange)
        }

        func textView(_ textView: UITextView, shouldChangeTextIn range: NSRange, replacementText text: String) -> Bool {
            guard text == "\n", range.length == 0, let textStorage else { return true }
            let fullText = textStorage.string as NSString
            let cursorLocation = range.location
            let lookupIndex = cursorLocation < fullText.length ? cursorLocation : max(cursorLocation - 1, 0)

            if let action = OrgHeadlineReturn.action(
                headline: textStorage.headline(atCharacterIndex: lookupIndex),
                cursorLocation: cursorLocation,
                text: fullText
            ) {
                apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
                return false
            }
            if let action = OrgListReturn.action(text: fullText, cursorLocation: cursorLocation) {
                apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
                return false
            }
            return true
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

            let (replaceRange, replacement, newSelection) = OrgEmphasisFormatting.toggle(range, in: text, with: emphasis)
            apply(replaceRange, replacement, selecting: newSelection)
        }

        /// Expands the keyword immediately before the cursor into its snippet text, if it
        /// matches one. Returns true if handled, false if the caller should fall back to
        /// folding, list demotion, or inserting a literal tab.
        func expandSnippet() -> Bool {
            guard let textView, let textStorage, textView.selectedRange.length == 0 else { return false }
            let text = textStorage.string as NSString
            guard let action = OrgSnippets.expansion(text: text, cursorLocation: textView.selectedRange.location) else { return false }
            return apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
        }

        /// Adds one indentation step to the list item under the cursor. Returns true if
        /// handled, false if the caller should fall back to inserting a literal tab.
        func demoteList() -> Bool {
            guard let textView, let textStorage else { return false }
            let text = textStorage.string as NSString
            guard let action = OrgListIndent.demote(text: text, cursorLocation: textView.selectedRange.location) else { return false }
            return apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
        }

        /// Removes one indentation step from the list item under the cursor.
        func promoteList() -> Bool {
            guard let textView, let textStorage else { return false }
            let text = textStorage.string as NSString
            guard let action = OrgListIndent.promote(text: text, cursorLocation: textView.selectedRange.location) else { return false }
            return apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
        }

        /// Adds one asterisk to the heading under the cursor.
        func demoteHeadline() -> Bool {
            guard let textView, let textStorage,
                  let headline = textStorage.headline(atCharacterIndex: textView.selectedRange.location) else { return false }
            let action = OrgHeadlineIndent.demote(headline: headline, cursorLocation: textView.selectedRange.location)
            return apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
        }

        /// Removes one asterisk from the heading under the cursor. Returns false if the
        /// heading is already at the top level.
        func promoteHeadline() -> Bool {
            guard let textView, let textStorage,
                  let headline = textStorage.headline(atCharacterIndex: textView.selectedRange.location) else { return false }
            guard let action = OrgHeadlineIndent.promote(headline: headline, cursorLocation: textView.selectedRange.location) else { return false }
            return apply(action.replaceRange, action.replacement, selectingLocation: action.newCursorLocation)
        }

        /// Replaces `range` with `replacement`, selecting just past the new text -- used by
        /// the find/replace bar, going through the same apply path as other edits.
        func replaceText(in range: NSRange, with replacement: String) -> Bool {
            let newSelection = NSRange(location: range.location, length: (replacement as NSString).length)
            return apply(range, replacement, selecting: newSelection)
        }

        @discardableResult
        private func apply(_ range: NSRange, _ replacement: String, selecting newSelection: NSRange) -> Bool {
            guard let textView,
                  let start = textView.position(from: textView.beginningOfDocument, offset: range.location),
                  let end = textView.position(from: start, offset: range.length),
                  let textRange = textView.textRange(from: start, to: end) else { return false }
            textView.replace(textRange, withText: replacement)

            if let newStart = textView.position(from: textView.beginningOfDocument, offset: newSelection.location),
               let newEnd = textView.position(from: newStart, offset: newSelection.length) {
                textView.selectedTextRange = textView.textRange(from: newStart, to: newEnd)
            }
            return true
        }

        @discardableResult
        private func apply(_ range: NSRange, _ replacement: String, selectingLocation location: Int) -> Bool {
            apply(range, replacement, selecting: NSRange(location: location, length: 0))
        }

        private func wordRange(in textView: UITextView, at index: Int) -> NSRange? {
            guard let position = textView.position(from: textView.beginningOfDocument, offset: index) else { return nil }
            // A cursor sitting right after a word (including at the end of the document) has
            // nothing ahead of it, so the forward direction alone misses the common case of
            // wrapping a word right after typing it -- fall back to backward in that case.
            let directions: [UITextStorageDirection] = [.forward, .backward]
            for direction in directions {
                if let range = textView.tokenizer.rangeEnclosingPosition(position, with: .word, inDirection: UITextDirection(rawValue: direction.rawValue)) {
                    let start = textView.offset(from: textView.beginningOfDocument, to: range.start)
                    let length = textView.offset(from: range.start, to: range.end)
                    return NSRange(location: start, length: length)
                }
            }
            return nil
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
