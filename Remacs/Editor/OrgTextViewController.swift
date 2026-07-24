//
//  OrgTextViewController.swift
//  Remacs
//
//  Bridges SwiftUI (namely the find/replace bar) to the underlying platform text view, so
//  it can read the current selection and drive selection/scrolling and undoable
//  replacements without needing to know about NSTextView/UITextView directly.
//

import Foundation
import Combine

final class OrgTextViewController: ObservableObject {
    @Published fileprivate(set) var selectedRange = NSRange(location: 0, length: 0)

    var selectHandler: ((NSRange) -> Void)?
    var replaceHandler: ((NSRange, String) -> Bool)?

    func select(_ range: NSRange) {
        selectHandler?(range)
    }

    @discardableResult
    func replace(_ range: NSRange, with replacement: String) -> Bool {
        replaceHandler?(range, replacement) ?? false
    }

    func updateSelection(_ range: NSRange) {
        guard selectedRange != range else { return }
        selectedRange = range
    }
}
