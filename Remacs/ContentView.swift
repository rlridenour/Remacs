//
//  ContentView.swift
//  Remacs
//
//  Created by Randall Ridenour on 7/23/26.
//

import SwiftUI

struct ContentView: View {
    @Binding var document: RemacsDocument

    var body: some View {
        TextEditor(text: $document.text)
    }
}

#Preview {
    ContentView(document: .constant(RemacsDocument()))
}
