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

    override var keyCommands: [UIKeyCommand]? {
        [UIKeyCommand(input: "\t", modifierFlags: [], action: #selector(handleTabCommand))]
    }

    @objc private func handleTabCommand() {
        if onToggleFoldAtSelection?() != true {
            insertText("\t")
        }
    }
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
