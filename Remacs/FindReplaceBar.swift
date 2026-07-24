//
//  FindReplaceBar.swift
//  Remacs
//
//  A find/replace bar that floats over the editor, in the style of Safari/Xcode's:
//  Command-F opens it (pre-filled with the current selection, if any), Command-G/
//  Shift-Command-G step to the next/previous match, and Return in the search field
//  also steps to the next match.
//

import SwiftUI

struct FindReplaceBar: View {
    @Binding var searchText: String
    @Binding var replaceText: String
    @Binding var showsReplace: Bool
    var searchFieldFocus: FocusState<Bool>.Binding
    var matchCount: Int
    var currentMatchNumber: Int?
    var onNext: () -> Void
    var onPrevious: () -> Void
    var onReplace: () -> Void
    var onReplaceAll: () -> Void
    var onClose: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Button {
                    showsReplace.toggle()
                } label: {
                    Image(systemName: showsReplace ? "chevron.down" : "chevron.right")
                        .frame(width: 14)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(showsReplace ? "Hide Replace" : "Show Replace")

                TextField("Find", text: $searchText)
                    .textFieldStyle(.roundedBorder)
                    .focused(searchFieldFocus)
                    .onSubmit(onNext)
                    .frame(minWidth: 160)

                Text(matchLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(minWidth: 72, alignment: .leading)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onPrevious) {
                    Image(systemName: "chevron.up")
                }
                .disabled(matchCount == 0)

                Button(action: onNext) {
                    Image(systemName: "chevron.down")
                }
                .disabled(matchCount == 0)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
            }

            if showsReplace {
                HStack(spacing: 8) {
                    Color.clear.frame(width: 14)

                    TextField("Replace", text: $replaceText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit(onReplace)
                        .frame(minWidth: 160)

                    Spacer(minLength: 0)

                    Button("Replace", action: onReplace)
                        .disabled(matchCount == 0)
                    Button("All", action: onReplaceAll)
                        .disabled(matchCount == 0)
                }
            }
        }
        .padding(8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) {
            Divider()
        }
    }

    private var matchLabel: String {
        guard !searchText.isEmpty else { return "" }
        guard matchCount > 0 else { return "No matches" }
        if let currentMatchNumber {
            return "\(currentMatchNumber) of \(matchCount)"
        }
        return matchCount == 1 ? "1 match" : "\(matchCount) matches"
    }
}
