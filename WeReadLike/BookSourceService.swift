//
//  BookSourceService.swift
//  WeReadLike
//
//  书源业务层：搜索 / 详情 / 目录 / 正文
//

import Foundation

// MARK: - URL 规则解析（支持 ,{...} 形式的 POST 配置）

struct UrlRule {
    var url: String
    var method: String = "GET"
    var body: String? = nil
    var headers: [String: String] = [:]

    static func parse(_ raw: String) -> UrlRule {
        let t = raw.trimmed()
        guard let r = t.range(of: ",{") else { return UrlRule(url: t) }
        let urlPart = String(t[..<r.lowerBound]).trimmed()
        let jsonPart = String(t[r.lowerBound...].dropFirst())
        var rule = UrlRule(url: urlPart)
        if let data = jsonPart.data(using: .utf8),
           let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            if let m = obj["method"] as? String { rule.method = m.uppercased() }
            if let b = obj["body"] as? String { rule.body = b }
            if let h = obj["headers"] as? [String: String] { rule.headers = h }
            if let h = obj["header"] as? [String: String] { rule.headers = h }
        }
        return rule
    }

    func resolve(key: String, page: Int, variables: [String: String]) -> UrlRule {
        func fill(_ s: String) -> String {
            var out = s
            out = out.replacingOccurrences(of: "{{key}}", with: key)
            out = out.replacingOccurrences(of: "{{searchKey}}", with: key)
            out = out.replacingOccurrences(of: "{{page}}", with: "\(page)")
            for (k, v) in variables {
                out = out.replacingOccurrences(of: "{{\(k)}}", with: v)
            }
            return out
        }
        var r = self
        r.url = fill(url)
        if let b = body { r.body = fill(b) }
        return r
    }
}

// MARK: - 服务

final class BookSourceService {

    static let shared = BookSourceService()

    private let client = HTTPClient.shared
    private let searchCache = NSCache<NSString, NSArray>()

    // MARK: 搜索

    func search(keyword: String, source: BookSource) async -> [SearchResult] {
        let key = keyword.trimmed()
        guard !key.isEmpty else { return [] }
        let cacheKey = "\(source.bookSourceUrl)|\(key)" as NSString
        if let cached = searchCache.object(forKey: cacheKey) as? [SearchResult], !cached.isEmpty {
            return cached
        }

        guard !source.searchUrl.trimmed().isEmpty else { return [] }

        let urls = source.searchUrl.components(separatedBy: "\n").filter { !$0.trimmed().isEmpty }
        for raw in urls {
            let rule = UrlRule.parse(raw).resolve(key: key, page: 1, variables: [:])
            var target = rule.url
            if !target.hasPrefix("http") {
                target = Self.absolute(target, base: source.bookSourceUrl)
            }
            do {
                let resp = try await client.fetch(url: target,
                                                  method: rule.method,
                                                  body: rule.body,
                                                  headers: merged(source.headers, rule.headers),
                                                  referer: source.bookSourceUrl)
                let results = parseSearchPage(resp.body, finalUrl: resp.finalUrl, source: source)
                if !results.isEmpty {
                    searchCache.setObject(results as NSArray, forKey: cacheKey)
                    return results
                }
            } catch {
                continue
            }
        }
        return []
    }

    private func parseSearchPage(_ html: String, finalUrl: String, source: BookSource) -> [SearchResult] {
        let runner = RuleRunner(html, baseUrl: finalUrl)
        let listRule = source.ruleSearch.bookList
        let nodes = listRule.trimmed().isEmpty ? [Any]() : runner.items(listRule)
        guard !nodes.isEmpty else { return [] }

        var out: [SearchResult] = []
        for node in nodes {
            let name = runner.string(source.ruleSearch.name, from: node)
            guard !name.trimmed().isEmpty else { continue }
            let author = runner.string(source.ruleSearch.author, from: node)
            let cover = runner.string(source.ruleSearch.coverUrl, from: node)
            let bookUrl = runner.string(source.ruleSearch.bookUrl, from: node)
            let intro = runner.string(source.ruleSearch.intro, from: node)
            let kind = runner.string(source.ruleSearch.kind, from: node)
            let last = runner.string(source.ruleSearch.lastChapter, from: node)
            let words = runner.string(source.ruleSearch.wordCount, from: node)

            var bu = bookUrl
            if bu.isEmpty, let n = node as? HTMLNode, let href = n.attr("href") { bu = href }
            bu = Self.absolute(bu, base: finalUrl)
            guard !bu.isEmpty else { continue }

            out.append(SearchResult(
                name: name.trimmed(),
                author: author.trimmed(),
                coverUrl: Self.absolute(cover, base: finalUrl),
                bookUrl: bu,
                intro: intro.trimmed(),
                kind: kind.trimmed(),
                lastChapter: last.trimmed(),
                wordCount: words.trimmed(),
                sourceUrl: source.bookSourceUrl,
                sourceName: source.bookSourceName
            ))
        }
        return out
    }

    // MARK: 详情

    func bookInfo(source: BookSource, bookUrl: String, fallbackName: String = "") async -> BookInfo {
        var info = BookInfo()
        info.name = fallbackName
        do {
            let resp = try await client.fetch(url: bookUrl,
                                              headers: source.headers,
                                              referer: source.bookSourceUrl)
            let runner = RuleRunner(resp.body, baseUrl: resp.finalUrl)
            let r = source.ruleBookInfo

            let n = runner.string(r.name)
            if !n.trimmed().isEmpty { info.name = n.trimmed() }
            info.author = runner.string(r.author).trimmed()
            let cover = runner.string(r.coverUrl)
            info.coverUrl = Self.absolute(cover, base: resp.finalUrl)
            info.intro = runner.string(r.intro).strippingHTML()
            info.kind = runner.string(r.kind).trimmed()
            info.lastChapter = runner.string(r.lastChapter).trimmed()
            info.wordCount = runner.string(r.wordCount).trimmed()
            var toc = runner.string(r.tocUrl)
            if toc.isEmpty { toc = resp.finalUrl }
            info.tocUrl = Self.absolute(toc, base: resp.finalUrl)

            if info.name.isEmpty {
                info.name = runner.string("tag.title").trimmed()
            }
        } catch {
            info.tocUrl = bookUrl
        }
        if info.tocUrl.isEmpty { info.tocUrl = bookUrl }
        return info
    }

    // MARK: 目录

    func toc(source: BookSource, tocUrl: String) async -> [Chapter] {
        var chapters: [Chapter] = []
        var visited = Set<String>()
        var next: String? = tocUrl
        var rounds = 0

        while let current = next, !current.isEmpty, rounds < 12, !visited.contains(current) {
            visited.insert(current)
            rounds += 1
            do {
                let resp = try await client.fetch(url: current,
                                                  headers: source.headers,
                                                  referer: source.bookSourceUrl)
                let runner = RuleRunner(resp.body, baseUrl: resp.finalUrl)
                let r = source.ruleToc
                let listRule = r.chapterList
                let nodes = listRule.trimmed().isEmpty ? [Any]() : runner.items(listRule)

                if nodes.isEmpty {
                    // 兜底：直接在当前页面找 a 标签
                    let fallback = CSSSelector.select("a", in: HTMLParser.parse(resp.body))
                    for a in fallback {
                        guard let href = a.attr("href") else { continue }
                        let title = a.textContent.trimmed()
                        if title.count < 2 { continue }
                        chapters.append(Chapter(title: title, url: Self.absolute(href, base: resp.finalUrl)))
                    }
                } else {
                    for node in nodes {
                        let title = runner.string(r.chapterName.isEmpty ? "text" : r.chapterName, from: node)
                        let url = runner.string(r.chapterUrl.isEmpty ? "href" : r.chapterUrl, from: node)
                        var u = Self.absolute(url, base: resp.finalUrl)
                        if u.isEmpty, let n = node as? HTMLNode, let href = n.attr("href") {
                            u = Self.absolute(href, base: resp.finalUrl)
                        }
                        guard !u.isEmpty else { continue }
                        chapters.append(Chapter(title: title.trimmed(), url: u))
                    }
                }

                let nextRule = r.nextTocUrl
                if nextRule.trimmed().isEmpty { break }
                let nv = runner.string(nextRule)
                if nv.trimmed().isEmpty { break }
                next = Self.absolute(nv, base: resp.finalUrl)
            } catch {
                break
            }
        }
        return dedupe(chapters)
    }

    // MARK: 正文

    func content(source: BookSource, chapterUrl: String) async -> String {
        var pieces: [String] = []
        var visited = Set<String>()
        var next: String? = chapterUrl
        var rounds = 0

        while let current = next, !current.isEmpty, rounds < 6, !visited.contains(current) {
            visited.insert(current)
            rounds += 1
            do {
                let resp = try await client.fetch(url: current,
                                                  headers: source.headers,
                                                  referer: source.bookSourceUrl)
                let runner = RuleRunner(resp.body, baseUrl: resp.finalUrl)
                let r = source.ruleContent

                var text = runner.string(r.content)
                if text.trimmed().isEmpty {
                    // 兜底：常见正文容器
                    let candidates = ["#content", "#chaptercontent", ".content", ".read-content",
                                      "#booktext", ".txtnav", "article", "#nr1", ".showtxt"]
                    for sel in candidates {
                        let nodes = CSSSelector.select(sel, in: HTMLParser.parse(resp.body))
                        if let first = nodes.first {
                            let t = first.textContent.trimmed()
                            if t.count > 30 { text = t; break }
                        }
                    }
                }
                pieces.append(text)

                let nextRule = r.nextContentUrl
                if nextRule.trimmed().isEmpty { break }
                let nv = runner.string(nextRule)
                if nv.trimmed().isEmpty { break }
                let abs = Self.absolute(nv, base: resp.finalUrl)
                if abs.isEmpty || abs == current { break }
                next = abs
            } catch {
                break
            }
        }

        let merged = pieces.joined(separator: "\n")
        return merged.strippingHTML().normalizedText()
    }

    // MARK: 工具

    static func absolute(_ url: String, base: String) -> String {
        let u = url.trimmed()
        if u.isEmpty { return "" }
        if u.hasPrefix("http://") || u.hasPrefix("https://") { return u }
        if u.hasPrefix("//") { return "https:" + u }
        guard let b = URL(string: base) else { return u }
        return URL(string: u, relativeTo: b)?.absoluteString ?? u
    }

    private func merged(_ a: [String: String], _ b: [String: String]) -> [String: String] {
        var out = a
        for (k, v) in b { out[k] = v }
        return out
    }

    private func dedupe(_ chapters: [Chapter]) -> [Chapter] {
        var seen = Set<String>()
        var out: [Chapter] = []
        for c in chapters {
            let key = c.url
            if seen.contains(key) { continue }
            seen.insert(key)
            out.append(c)
        }
        return out
    }
}
