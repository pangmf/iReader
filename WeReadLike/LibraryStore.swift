//
//  LibraryStore.swift
//  WeReadLike
//
//  全局状态：书架、书源、阅读设置、正文缓存
//

import Foundation
import SwiftUI
import CryptoKit

@MainActor
final class LibraryStore: ObservableObject {

    @Published var books: [ShelfBook] = []
    @Published var sources: [BookSource] = []
    @Published var settings = ReaderSettings()
    @Published var loadingMessage: String? = nil
    @Published var toast: String? = nil

    private let fm = FileManager.default

    // MARK: 路径

    private var docs: URL {
        fm.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var booksURL: URL { docs.appendingPathComponent("books.json") }
    private var sourcesURL: URL { docs.appendingPathComponent("sources.json") }
    private var settingsURL: URL { docs.appendingPathComponent("settings.json") }
    private var cacheDir: URL {
        let d = docs.appendingPathComponent("chapter_cache", isDirectory: true)
        if !fm.fileExists(atPath: d.path) {
            try? fm.createDirectory(at: d, withIntermediateDirectories: true)
        }
        return d
    }

    init() {
        load()
    }

    // MARK: 读写

    func load() {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970

        if let data = try? Data(contentsOf: booksURL),
           let list = try? decoder.decode([ShelfBook].self, from: data) {
            books = list
        }
        if let data = try? Data(contentsOf: sourcesURL),
           let list = try? decoder.decode([BookSource].self, from: data) {
            sources = list
        }
        if let data = try? Data(contentsOf: settingsURL),
           let s = try? JSONDecoder().decode(ReaderSettings.self, from: data) {
            settings = s
        }
    }

    func saveBooks() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        if let data = try? encoder.encode(books) {
            try? data.write(to: booksURL, options: .atomic)
        }
    }

    func saveSources() {
        if let data = try? JSONEncoder().encode(sources) {
            try? data.write(to: sourcesURL, options: .atomic)
        }
    }

    func saveSettings() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: settingsURL, options: .atomic)
        }
    }

    // MARK: 书源

    @discardableResult
    func importSources(from data: Data) -> Int {
        let parsed = Self.decodeSources(data)
        guard !parsed.isEmpty else { return 0 }
        var added = 0
        for var s in parsed {
            guard !s.bookSourceUrl.trimmed().isEmpty, !s.bookSourceName.trimmed().isEmpty else { continue }
            if let idx = sources.firstIndex(where: { $0.bookSourceUrl == s.bookSourceUrl }) {
                s.enabled = sources[idx].enabled
                sources[idx] = s
            } else {
                sources.append(s)
                added += 1
            }
        }
        saveSources()
        return added
    }

    func importSources(from text: String) -> Int {
        guard let data = text.data(using: .utf8) else { return 0 }
        return importSources(from: data)
    }

    func importSources(fromURL urlString: String) async throws -> Int {
        let resp = try await HTTPClient.shared.fetch(url: urlString)
        var text = resp.body.trimmed()
        // 兼容 JSON 数组 / 对象
        if let data = text.data(using: .utf8) {
            let n = importSources(from: data)
            if n > 0 { return n }
        }
        // 兼容带 BOM 或首尾说明文字
        if let start = text.firstIndex(where: { $0 == "[" || $0 == "{" }),
           let end = text.lastIndex(where: { $0 == "]" || $0 == "}" }) {
            text = String(text[start...end])
            if let data = text.data(using: .utf8) {
                return importSources(from: data)
            }
        }
        return 0
    }

    func deleteSource(at offsets: IndexSet) {
        sources.remove(atOffsets: offsets)
        saveSources()
    }

    func deleteSource(id: String) {
        sources.removeAll { $0.id == id }
        saveSources()
    }

    func toggleSource(id: String) {
        if let idx = sources.firstIndex(where: { $0.id == id }) {
            sources[idx].enabled.toggle()
            saveSources()
        }
    }

    var enabledSources: [BookSource] {
        sources.filter { $0.enabled }
    }

    static func decodeSources(_ data: Data) -> [BookSource] {
        let decoder = JSONDecoder()

        // 1. 直接数组
        if let list = try? decoder.decode([BookSource].self, from: data), !list.isEmpty {
            return list
        }
        // 2. {bookSources: [...]}
        if let raw = try? JSONSerialization.jsonObject(with: data),
           let obj = raw as? [String: Any] {
            for key in ["bookSources", "sources", "data", "list"] {
                if let arr = obj[key] as? [Any],
                   let sub = try? JSONSerialization.data(withJSONObject: arr),
                   let list = try? decoder.decode([BookSource].self, from: sub) {
                    return list
                }
            }
            if let sub = try? JSONSerialization.data(withJSONObject: obj),
               let one = try? decoder.decode(BookSource.self, from: sub) {
                return [one]
            }
        }
        // 3. 单个对象
        if let one = try? decoder.decode(BookSource.self, from: data) {
            return [one]
        }
        // 4. 文本里夹带 JSON
        if let text = String(data: data, encoding: .utf8),
           let start = text.firstIndex(where: { $0 == "[" }),
           let end = text.lastIndex(where: { $0 == "]" }),
           let sub = String(text[start...end]).data(using: .utf8),
           let list = try? decoder.decode([BookSource].self, from: sub) {
            return list
        }
        return []
    }

    // MARK: 书架

    func isOnShelf(bookUrl: String) -> Bool {
        books.contains { $0.id == bookUrl }
    }

    @discardableResult
    func addToShelf(_ result: SearchResult, info: BookInfo, chapters: [Chapter]) -> ShelfBook {
        if let idx = books.firstIndex(where: { $0.id == result.bookUrl }) {
            books[idx].chapters = chapters
            books[idx].tocUrl = info.tocUrl
            if !info.coverUrl.isEmpty { books[idx].coverUrl = info.coverUrl }
            if !info.intro.isEmpty { books[idx].intro = info.intro }
            saveBooks()
            return books[idx]
        }
        let book = ShelfBook(
            id: result.bookUrl,
            name: result.name.isEmpty ? info.name : result.name,
            author: result.author.isEmpty ? info.author : result.author,
            coverUrl: info.coverUrl.isEmpty ? result.coverUrl : info.coverUrl,
            intro: info.intro.isEmpty ? result.intro : info.intro,
            kind: info.kind.isEmpty ? result.kind : info.kind,
            lastChapter: info.lastChapter.isEmpty ? result.lastChapter : info.lastChapter,
            wordCount: info.wordCount.isEmpty ? result.wordCount : info.wordCount,
            sourceUrl: result.sourceUrl,
            sourceName: result.sourceName,
            tocUrl: info.tocUrl,
            chapters: chapters,
            currentChapter: 0,
            addedAt: Date(),
            lastReadAt: Date()
        )
        books.insert(book, at: 0)
        saveBooks()
        return book
    }

    func removeFromShelf(_ book: ShelfBook) {
        books.removeAll { $0.id == book.id }
        saveBooks()
    }

    func updateProgress(bookId: String, chapter: Int) {
        guard let idx = books.firstIndex(where: { $0.id == bookId }) else { return }
        books[idx].currentChapter = max(0, min(chapter, max(0, books[idx].chapters.count - 1)))
        books[idx].lastReadAt = Date()
        saveBooks()
    }

    func book(id: String) -> ShelfBook? {
        books.first { $0.id == id }
    }

    func source(url: String) -> BookSource? {
        sources.first { $0.bookSourceUrl == url }
    }

    // MARK: 正文缓存

    private func cacheFile(for url: String) -> URL {
        let digest = SHA256.hash(data: Data(url.utf8))
        let name = digest.compactMap { String(format: "%02x", $0) }.joined()
        return cacheDir.appendingPathComponent(name + ".txt")
    }

    func cachedContent(for url: String) -> String? {
        let f = cacheFile(for: url)
        guard let data = try? Data(contentsOf: f),
              let s = String(data: data, encoding: .utf8),
              !s.trimmed().isEmpty else { return nil }
        return s
    }

    func storeContent(_ text: String, for url: String) {
        let f = cacheFile(for: url)
        try? text.data(using: .utf8)?.write(to: f, options: .atomic)
    }

    /// 阅读器取正文：先缓存，再抓取
    func chapterContent(book: ShelfBook, index: Int) async -> String {
        guard index >= 0, index < book.chapters.count else { return "章节不存在" }
        let chapter = book.chapters[index]
        if let cached = cachedContent(for: chapter.url) { return cached }

        guard let source = source(url: book.sourceUrl) else {
            return "找不到书源：\(book.sourceName)"
        }
        let text = await BookSourceService.shared.content(source: source, chapterUrl: chapter.url)
        if text.trimmed().isEmpty {
            return "本章内容获取失败，可能是书源规则失效或网站限制。"
        }
        storeContent(text, for: chapter.url)
        return text
    }

    // MARK: 提示

    func flash(_ message: String) {
        toast = message
        Task {
            try? await Task.sleep(nanoseconds: 2_200_000_000)
            if self.toast == message { self.toast = nil }
        }
    }
}

// MARK: - 阅读设置

struct ReaderSettings: Codable, Equatable {
    var fontSize: Double = 18
    var lineSpacing: Double = 9
    var themeIndex: Int = 1
    var scrollMode: Bool = false
}
