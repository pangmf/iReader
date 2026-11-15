//
//  Models.swift
//  WeReadLike
//
//  数据模型：书源（Legado / 阅读 3.0 格式）、书籍、章节、搜索结果
//

import Foundation

// MARK: - 容错 JSON 解码

struct AnyCodingKey: CodingKey {
    var stringValue: String
    var intValue: Int?
    init(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) {
        self.intValue = intValue
        self.stringValue = "\(intValue)"
    }
}

extension KeyedDecodingContainer where Key == AnyCodingKey {

    func str(_ key: String) -> String? {
        let k = AnyCodingKey(stringValue: key)
        if let v = try? decode(String.self, forKey: k) { return v }
        if let v = try? decode(Int.self, forKey: k) { return String(v) }
        if let v = try? decode(Double.self, forKey: k) { return Self.trim(v) }
        if let v = try? decode(Bool.self, forKey: k) { return v ? "true" : "false" }
        return nil
    }

    func intValue(_ key: String) -> Int {
        let k = AnyCodingKey(stringValue: key)
        if let v = try? decode(Int.self, forKey: k) { return v }
        if let v = try? decode(Double.self, forKey: k) { return Int(v) }
        if let v = try? decode(String.self, forKey: k), let n = Int(v) { return n }
        return 0
    }

    func boolValue(_ key: String, default def: Bool = false) -> Bool {
        let k = AnyCodingKey(stringValue: key)
        if let v = try? decode(Bool.self, forKey: k) { return v }
        if let v = try? decode(String.self, forKey: k) { return v == "true" || v == "1" }
        if let v = try? decode(Int.self, forKey: k) { return v != 0 }
        return def
    }

    func sub(_ key: String) -> KeyedDecodingContainer<AnyCodingKey>? {
        try? nestedContainer(keyedBy: AnyCodingKey.self, forKey: AnyCodingKey(stringValue: key))
    }

    private static func trim(_ d: Double) -> String {
        if d == d.rounded() && abs(d) < 1e15 { return String(Int(d)) }
        return String(d)
    }
}

// MARK: - 书源

struct BookSource: Codable, Identifiable, Hashable {

    var bookSourceUrl: String = ""
    var bookSourceName: String = ""
    var bookSourceGroup: String = ""
    var bookSourceType: Int = 0
    var bookSourceComment: String = ""
    var enabled: Bool = true
    var enabledExplore: Bool = false
    var header: String = ""
    var searchUrl: String = ""
    var exploreUrl: String = ""
    var ruleSearch: SearchRule = SearchRule()
    var ruleBookInfo: BookInfoRule = BookInfoRule()
    var ruleToc: TocRule = TocRule()
    var ruleContent: ContentRule = ContentRule()

    var id: String { bookSourceUrl }

    var host: String {
        if let h = URL(string: bookSourceUrl)?.host { return h }
        return bookSourceUrl
    }

    var displayGroup: String {
        bookSourceGroup.isEmpty ? "未分组" : bookSourceGroup
    }

    // 书源请求头（可为 JSON，也可为 "Key: Value\nKey2: Value2"）
    var headers: [String: String] {
        var result: [String: String] = [:]
        let raw = header.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return result }
        if raw.hasPrefix("{"), let data = raw.data(using: .utf8),
           let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            for (k, v) in dict { result[k] = "\(v)" }
            return result
        }
        for line in raw.components(separatedBy: "\n") {
            let parts = line.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
            if parts.count == 2 {
                let key = parts[0].trimmingCharacters(in: .whitespaces)
                let value = parts[1].trimmingCharacters(in: .whitespaces)
                if !key.isEmpty { result[key] = value }
            }
        }
        return result
    }

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: AnyCodingKey.self)
        bookSourceUrl = c.str("bookSourceUrl") ?? ""
        bookSourceName = c.str("bookSourceName") ?? ""
        bookSourceGroup = c.str("bookSourceGroup") ?? ""
        bookSourceType = c.intValue("bookSourceType")
        bookSourceComment = c.str("bookSourceComment") ?? ""
        enabled = c.boolValue("enabled", default: true)
        enabledExplore = c.boolValue("enabledExplore", default: false)
        header = c.str("header") ?? ""
        searchUrl = c.str("searchUrl") ?? ""
        exploreUrl = c.str("exploreUrl") ?? ""
        if let sc = c.sub("ruleSearch") { ruleSearch = SearchRule(container: sc) }
        if let bc = c.sub("ruleBookInfo") { ruleBookInfo = BookInfoRule(container: bc) }
        if let tc = c.sub("ruleToc") { ruleToc = TocRule(container: tc) }
        if let cc = c.sub("ruleContent") { ruleContent = ContentRule(container: cc) }
    }
}

struct SearchRule: Codable, Hashable {
    var checkKeyWord: String = ""
    var bookList: String = ""
    var name: String = ""
    var author: String = ""
    var kind: String = ""
    var wordCount: String = ""
    var lastChapter: String = ""
    var intro: String = ""
    var coverUrl: String = ""
    var bookUrl: String = ""

    init() {}

    init(container c: KeyedDecodingContainer<AnyCodingKey>) {
        checkKeyWord = c.str("checkKeyWord") ?? ""
        bookList = c.str("bookList") ?? ""
        name = c.str("name") ?? ""
        author = c.str("author") ?? ""
        kind = c.str("kind") ?? ""
        wordCount = c.str("wordCount") ?? ""
        lastChapter = c.str("lastChapter") ?? ""
        intro = c.str("intro") ?? ""
        coverUrl = c.str("coverUrl") ?? ""
        bookUrl = c.str("bookUrl") ?? ""
    }
}

struct BookInfoRule: Codable, Hashable {
    var initRule: String = ""
    var name: String = ""
    var author: String = ""
    var kind: String = ""
    var wordCount: String = ""
    var lastChapter: String = ""
    var intro: String = ""
    var coverUrl: String = ""
    var tocUrl: String = ""
    var canReName: String = ""

    init() {}

    init(container c: KeyedDecodingContainer<AnyCodingKey>) {
        initRule = c.str("init") ?? ""
        name = c.str("name") ?? ""
        author = c.str("author") ?? ""
        kind = c.str("kind") ?? ""
        wordCount = c.str("wordCount") ?? ""
        lastChapter = c.str("lastChapter") ?? ""
        intro = c.str("intro") ?? ""
        coverUrl = c.str("coverUrl") ?? ""
        tocUrl = c.str("tocUrl") ?? ""
        canReName = c.str("canReName") ?? ""
    }
}

struct TocRule: Codable, Hashable {
    var chapterList: String = ""
    var chapterName: String = ""
    var chapterUrl: String = ""
    var nextTocUrl: String = ""
    var isVolume: String = ""
    var updateTime: String = ""

    init() {}

    init(container c: KeyedDecodingContainer<AnyCodingKey>) {
        chapterList = c.str("chapterList") ?? ""
        chapterName = c.str("chapterName") ?? ""
        chapterUrl = c.str("chapterUrl") ?? ""
        nextTocUrl = c.str("nextTocUrl") ?? ""
        isVolume = c.str("isVolume") ?? ""
        updateTime = c.str("updateTime") ?? ""
    }
}

struct ContentRule: Codable, Hashable {
    var content: String = ""
    var nextContentUrl: String = ""
    var webJs: String = ""
    var sourceRegex: String = ""
    var replaceRegex: String = ""

    init() {}

    init(container c: KeyedDecodingContainer<AnyCodingKey>) {
        content = c.str("content") ?? ""
        nextContentUrl = c.str("nextContentUrl") ?? ""
        webJs = c.str("webJs") ?? ""
        sourceRegex = c.str("sourceRegex") ?? ""
        replaceRegex = c.str("replaceRegex") ?? ""
    }
}

// MARK: - 运行时模型

struct Chapter: Codable, Identifiable, Hashable {
    var title: String
    var url: String
    var id: String { url + "#" + title }
}

struct SearchResult: Identifiable, Hashable {
    var id: String { sourceUrl + "#" + bookUrl }
    var name: String
    var author: String
    var coverUrl: String
    var bookUrl: String
    var intro: String
    var kind: String
    var lastChapter: String
    var wordCount: String
    var sourceUrl: String
    var sourceName: String
}

struct BookInfo {
    var name: String = ""
    var author: String = ""
    var coverUrl: String = ""
    var intro: String = ""
    var kind: String = ""
    var lastChapter: String = ""
    var wordCount: String = ""
    var tocUrl: String = ""
}

// MARK: - 书架

struct ShelfBook: Codable, Identifiable, Hashable {
    var id: String
    var name: String
    var author: String
    var coverUrl: String
    var intro: String
    var kind: String
    var lastChapter: String
    var wordCount: String
    var sourceUrl: String
    var sourceName: String
    var tocUrl: String
    var chapters: [Chapter]
    var currentChapter: Int
    var addedAt: Date
    var lastReadAt: Date

    var progressText: String {
        guard !chapters.isEmpty else { return "未开始" }
        let p = Double(currentChapter + 1) / Double(chapters.count)
        if currentChapter <= 0 && p <= 0.001 { return "未开始" }
        return "读至 \(Int(p * 100))%"
    }
}
