//
//  SnippetsMenu.swift
//  Remacs
//
//  A toolbar menu for choosing, creating, and (on macOS) opening the snippets org file.
//  On iOS, the snippets file is opened like any other document, from the file browser.
//

import SwiftUI
import UniformTypeIdentifiers

extension View {
    func snippetsMenu() -> some View {
        modifier(SnippetsMenu())
    }
}

private struct SnippetsMenu: ViewModifier {
    @ObservedObject private var library = OrgSnippetLibrary.shared
    @State private var isChoosingFile = false
    @State private var isCreatingFile = false
    @State private var errorMessage: String?
    #if os(macOS)
    @Environment(\.openDocument) private var openDocument
    #endif

    func body(content: Content) -> some View {
        content
            .toolbar {
                ToolbarItem {
                    Menu("Snippets", systemImage: "text.insert") {
                        Section(library.fileURL?.lastPathComponent ?? "Built-in Snippets") {
                            #if os(macOS)
                            Button("Edit Snippets", action: editSnippets)
                                .disabled(library.fileURL == nil)
                            #endif
                            Button("Choose Snippets File…") { isChoosingFile = true }
                            Button("New Snippets File…") { isCreatingFile = true }
                            if library.fileURL != nil {
                                Button("Use Built-in Snippets") { library.useBuiltIn() }
                            }
                        }
                    }
                }
            }
            .fileImporter(isPresented: $isChoosingFile, allowedContentTypes: RemacsDocument.readableContentTypes) { result in
                useSnippetsFile(result)
            }
            // Starts the new file with the built-in snippets so there's something to edit.
            .fileExporter(
                isPresented: $isCreatingFile,
                document: RemacsDocument(text: OrgSnippets.defaultLibraryText),
                contentType: RemacsDocument.readableContentTypes[0],
                defaultFilename: "snippets"
            ) { result in
                useSnippetsFile(result)
            }
            .alert("Snippets File", isPresented: Binding(
                get: { errorMessage != nil },
                set: { if !$0 { errorMessage = nil } }
            )) {
                Button("OK") {}
            } message: {
                Text(errorMessage ?? "")
            }
    }

    private func useSnippetsFile(_ result: Result<URL, Error>) {
        do {
            try library.use(result.get())
        } catch CocoaError.userCancelled {
            // Nothing to report.
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    #if os(macOS)
    private func editSnippets() {
        guard let url = library.fileURL else { return }
        Task {
            do {
                try await openDocument(at: url)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
    #endif
}
