//
//  RemacsApp.swift
//  Remacs
//
//  Created by Randall Ridenour on 7/23/26.
//

import SwiftUI

@main
struct RemacsApp: App {
    var body: some Scene {
        DocumentGroup(newDocument: RemacsDocument()) { file in
            ContentView(document: file.$document)
        }
    }
}
