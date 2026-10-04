//
//  ContentView.swift
//  Remacs
//
//  Created by Randall Ridenour on 7/23/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: RemacsDocument
    @StateObject private var textController = OrgTextViewController()
    @State private var isFindBarVisible = false
    @State private var searchText = ""
    @State private var replaceText = ""
    @State private var showsReplace = false
    @FocusState private var isSearchFieldFocused: Bool

    var body: some View {
        ZStack(alignment: .top) {
            OrgTextView(text: $document.text, controller: textController)

            if isFindBarVisible {
                FindReplaceBar(
                    searchText: $searchText,
                    replaceText: $replaceText,
                    showsReplace: $showsReplace,
                    searchFieldFocus: $isSearchFieldFocused,
                    matchCount: matches.count,
                    currentMatchNumber: currentMatchNumber,
                    onNext: findNext,
                    onPrevious: findPrevious,
                    onReplace: replaceCurrent,
                    onReplaceAll: replaceAll,
                    onClose: closeFindBar
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.default, value: isFindBarVisible)
        .snippetsMenu()
        .background {
            Group {
                Button("Find", action: openFindBar)
                    .keyboardShortcut("f", modifiers: .command)
                Button("Find Next", action: findNext)
                    .keyboardShortcut("g", modifiers: .command)
                Button("Find Previous", action: findPrevious)
                    .keyboardShortcut("g", modifiers: [.command, .shift])
                Button("Close Find", action: closeFindBar)
                    .keyboardShortcut(.escape, modifiers: [])
            }
            .hidden()
        }
    }

    private var matches: [NSRange] {
        OrgFind.matches(of: searchText, in: document.text as NSString)
    }

    private var currentMatchNumber: Int? {
        matches.firstIndex(of: textController.selectedRange).map { $0 + 1 }
    }

    private func openFindBar() {
        let ns = document.text as NSString
        let selection = textController.selectedRange
        if selection.length > 0, selection.location + selection.length <= ns.length {
            searchText = ns.substring(with: selection)
        }
        isFindBarVisible = true
        isSearchFieldFocused = true
    }

    private func closeFindBar() {
        isFindBarVisible = false
        isSearchFieldFocused = false
    }

    private func findNext() {
        guard let index = OrgFind.indexAfter(textController.selectedRange, in: matches) else { return }
        textController.select(matches[index])
    }

    private func findPrevious() {
        guard let index = OrgFind.indexBefore(textController.selectedRange, in: matches) else { return }
        textController.select(matches[index])
    }

    /// Replaces the currently selected match, then advances to the next one. No-ops if the
    /// current selection isn't actually one of the search matches.
    private func replaceCurrent() {
        let range = textController.selectedRange
        guard matches.contains(range) else { return }
        textController.replace(range, with: replaceText)
        findNext()
    }

    /// Replaces every match. Works from the last match backwards so that replacing one
    /// occurrence never shifts the character offsets of the ones still to be replaced.
    private func replaceAll() {
        for range in matches.reversed() {
            textController.replace(range, with: replaceText)
        }
    }
}

#Preview {
    ContentView(document: .constant(RemacsDocument()))
}
