//
//  OrgSnippetLibrary.swift
//  Remacs
//
//  The user's snippets file: an org file they chose, remembered across launches with a
//  security-scoped bookmark (the app is sandboxed) and re-read whenever it changes on
//  disk, so edits take effect on the next Tab without restarting. Falls back to the
//  built-in snippets when no file is chosen or it can't be read.
//

import Foundation
import Combine

final class OrgSnippetLibrary: ObservableObject {
    static let shared = OrgSnippetLibrary()

    private static let bookmarkKey = "SnippetsFileBookmark"
    #if os(macOS)
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = .withSecurityScope
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = .withSecurityScope
    #else
    private static let bookmarkCreationOptions: URL.BookmarkCreationOptions = []
    private static let bookmarkResolutionOptions: URL.BookmarkResolutionOptions = []
    #endif

    /// The chosen snippets file, or nil when using the built-in snippets. Its security
    /// scope stays open for as long as it's the snippets file.
    @Published private(set) var fileURL: URL?

    private var cachedTemplates: [String: String]?
    private var cachedModificationDate: Date?

    private init() {
        resolveBookmark()
    }

    /// Keyword -> template, from the snippets file if there is one.
    var templates: [String: String] {
        guard let fileURL else { return OrgSnippets.builtInTemplates }
        let modified = try? fileURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        if let cachedTemplates, modified == cachedModificationDate {
            return cachedTemplates
        }
        guard let text = Self.read(fileURL) else {
            return cachedTemplates ?? OrgSnippets.builtInTemplates
        }
        let templates = OrgSnippets.parseLibrary(text)
        cachedTemplates = templates
        cachedModificationDate = modified
        return templates
    }

    /// Makes `url` the snippets file. `url` must be one the user just picked (e.g. from a
    /// file importer or exporter), which is what grants access to it.
    func use(_ url: URL) throws {
        let isAccessing = url.startAccessingSecurityScopedResource()
        defer { if isAccessing { url.stopAccessingSecurityScopedResource() } }
        let bookmark = try url.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil)
        UserDefaults.standard.set(bookmark, forKey: Self.bookmarkKey)
        resolveBookmark()
    }

    /// Forgets the snippets file and goes back to the built-in snippets.
    func useBuiltIn() {
        UserDefaults.standard.removeObject(forKey: Self.bookmarkKey)
        resolveBookmark()
    }

    private func resolveBookmark() {
        fileURL?.stopAccessingSecurityScopedResource()
        fileURL = nil
        cachedTemplates = nil
        cachedModificationDate = nil

        guard let bookmark = UserDefaults.standard.data(forKey: Self.bookmarkKey) else { return }
        var isStale = false
        guard let url = try? URL(resolvingBookmarkData: bookmark, options: Self.bookmarkResolutionOptions, relativeTo: nil, bookmarkDataIsStale: &isStale) else { return }
        _ = url.startAccessingSecurityScopedResource()
        if isStale, let fresh = try? url.bookmarkData(options: Self.bookmarkCreationOptions, includingResourceValuesForKeys: nil, relativeTo: nil) {
            UserDefaults.standard.set(fresh, forKey: Self.bookmarkKey)
        }
        fileURL = url
    }

    /// Reads through a file coordinator, which also downloads the file first if it's in
    /// iCloud Drive and not yet on this device.
    private static func read(_ url: URL) -> String? {
        var text: String?
        var coordinatorError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: url, options: [], error: &coordinatorError) { readURL in
            text = try? String(contentsOf: readURL, encoding: .utf8)
        }
        return text
    }
}
