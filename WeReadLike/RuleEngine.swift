//
//  RuleEngine.swift
//  WeReadLike
//
//  Legado / 阅读 3.0 书源规则引擎
//  支持：@css: / @xpath: / @json: / 默认 HTML 规则 / @ 多级步骤
//        {{JS}} 内联脚本 / ## 正则替换 / && 与 || 组合 / 变量 {{key}} {{page}}
//

import Foundation
import JavaScriptCore

// MARK: - JS 执行

enum JSRuntime {

    static func evaluate(_ code: String, bindings: [String: Any]) -> String? {
        let ctx = JSContext()
        ctx?.exceptionHandler = { _, _ in }
        for (k, v) in bindings { ctx?.setObject(v, forKeyedSubscript: k as NSString) }
        guard let value = ctx?.evaluateScript(code) else { return nil }
        if value.isUndefined || value.isNull { return nil }
        if let s = value.toString() {
            let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
            if t == "undefined" || t == "null" { return nil }
            return s
        }
        return nil
    }
}

// MARK: - 规则执行器

final class RuleRunner {

    let baseUrl: String
    let isJSON: Bool
    var variables: [String: String]

    private let source: String
    private lazy var htmlRoot: HTMLNode = HTMLParser.parse(source)
    private lazy var jsonRoot: Any = {
        if let obj = try? JSONSerialization.jsonObject(with: Data(source.utf8)) { return obj }
        // 尝试截取第一个 { 或 [ 之后的内容
        if let start = source.firstIndex(where: { $0 == "{" || $0 == "[" }) {
            let sub = String(source[start...])
            if let obj = try? JSONSerialization.jsonObject(with: Data(sub.utf8)) { return obj }
        }
        return [String: Any]()
    }()

    init(_ source: String, baseUrl: String, isJSON: Bool = false, variables: [String: String] = [:]) {
        self.source = source
        self.baseUrl = baseUrl
        self.isJSON = isJSON
        self.variables = variables
    }

    // MARK: 公共入口

    func items(_ rule: String) -> [Any] {
        let root: Any = isJSON ? jsonRoot : htmlRoot
        return evaluate(rule, from: [root])
    }

    func string(_ rule: String) -> String {
        if rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return isJSON ? "" : htmlRoot.textContent.trimmed()
        }
        return firstString(items(rule))
    }

    func items(_ rule: String, from item: Any) -> [Any] {
        evaluate(rule, from: [item])
    }

    func string(_ rule: String, from item: Any) -> String {
        if rule.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return plainString(item)
        }
        return firstString(items(rule, from: item))
    }

    // MARK: 求值核心

    private func evaluate(_ rule: String, from items: [Any]) -> [Any] {
        var text = substituteVariables(rule)
        let (cleanRule, jsCodes) = Self.extractJS(text)
        text = cleanRule

        // || 取第一个非空
        var orResult: [Any] = []
        for orPart in Self.splitTop(text, "||") {
            // && 依次串联
            var andResult: [Any] = []
            var andOk = true
            let andParts = Self.splitTop(orPart, "&&")
            for (i, part) in andParts.enumerated() {
                let (pureRule, replacers) = Self.splitRegex(part)
                var r = runChain(pureRule, from: (i == 0 ? items : andResult))
                if r.isEmpty { andOk = false; break }
                if !replacers.isEmpty {
                    r = applyReplacers(r, replacers)
                }
                andResult = r
            }
            if andOk && !andResult.isEmpty {
                orResult = andResult
                break
            }
        }

        if orResult.isEmpty { return [] }

        // 还原内联 JS
        if !jsCodes.isEmpty {
            orResult = orResult.map { value -> Any in
                if let s = value as? String {
                    var out = s
                    for (idx, code) in jsCodes.enumerated() {
                        let token = "\u{1}\(idx)\u{1}"
                        if out.contains(token) {
                            let v = JSRuntime.evaluate(code, bindings: jsBindings()) ?? ""
                            out = out.replacingOccurrences(of: token, with: v)
                        }
                    }
                    return out
                }
                return value
            }
        }
        return orResult
    }

    private func runChain(_ rule: String, from items: [Any]) -> [Any] {
        let steps = rule.components(separatedBy: "@")
        var current = items
        for raw in steps {
            let step = raw.trimmingCharacters(in: .whitespacesAndNewlines)
            if step.isEmpty { continue }
            var next: [Any] = []
            for item in current {
                next.append(contentsOf: applyStep(step, to: item))
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
    }

    private func applyStep(_ rawStep: String, to item: Any) -> [Any] {
        let s = rawStep.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.isEmpty { return [item] }

        // 1. 显式前缀
        if let rest = s.removingPrefixAny(["@css:", "css:"]) {
            return htmlSelect(rest, from: item)
        }
        if let rest = s.removingPrefixAny(["@xpath:", "xpath:"]) {
            return xpathSelect(rest, from: item)
        }
        if let rest = s.removingPrefixAny(["json:", "@json:"]) {
            return jsonSelect(rest, from: item)
        }
        if let rest = s.removingPrefixAny(["regex:", "@regex:"]) {
            return regexSelect(rest, from: item)
        }

        if let node = item as? HTMLNode {
            return applyHTMLStep(s, node)
        }
        if let dict = item as? [String: Any] {
            return applyJSONStep(s, dict)
        }
        if let arr = item as? [Any] {
            var out: [Any] = []
            for e in arr { out.append(contentsOf: applyStep(s, to: e)) }
            return out
        }
        if let str = item as? String {
            // 字符串节点：允许直接取正则
            if let v = regexFirst(s, in: str) { return [v] }
            return [str]
        }
        if let num = item as? NSNumber {
            return [num.stringValue]
        }
        return [item]
    }

    private func applyHTMLStep(_ s: String, _ node: HTMLNode) -> [Any] {
        switch s {
        case "text", "textNodes", "allText":
            return [node.textContent]
        case "ownText":
            return [node.ownText]
        case "html", "outerHtml", "all":
            return [node.outerHTML]
        case "children":
            return node.children.filter { !$0.isText }
        case "text.0":
            return [node.textContent]
        default:
            break
        }

        if s.hasPrefix("tag.") {
            let rest = String(s.dropFirst(4))
            let comps = rest.split(separator: ".").map { String($0) }
            var nodes = node.descendants().filter { !$0.isText && $0.tag == comps[0].lowercased() }
            if comps.count > 1, let idx = Int(comps[1]) {
                nodes = (idx >= 0 && idx < nodes.count) ? [nodes[idx]] : []
            }
            return nodes
        }
        if s.hasPrefix("class.") {
            return htmlSelect("." + String(s.dropFirst(6)), from: node)
        }
        if s.hasPrefix("id.") {
            return htmlSelect("#" + String(s.dropFirst(3)), from: node)
        }
        if s.hasPrefix("[") {
            return htmlSelect(s, from: node)
        }
        if let idx = Int(s), idx >= 0 {
            let kids = node.children.filter { !$0.isText }
            return idx < kids.count ? [kids[idx]] : []
        }
        if let v = node.attr(s) { return [v] }
        if let v = node.attr(s.lowercased()) { return [v] }

        // 兜底：当作 CSS 选择器
        let r = htmlSelect(s, from: node)
        return r
    }

    private func applyJSONStep(_ s: String, _ obj: [String: Any]) -> [Any] {
        if let v = obj[s] { return [v] }
        if s.hasPrefix("$") || s.contains("[") || s.contains(".") {
            let r = JSONPathLite.query(obj, path: s)
            return r
        }
        return []
    }

    private func htmlSelect(_ selector: String, from item: Any) -> [Any] {
        if let node = item as? HTMLNode {
            return CSSSelector.select(selector, in: node)
        }
        if let str = item as? String {
            return CSSSelector.select(selector, in: HTMLParser.parse(str))
        }
        if let arr = item as? [Any] {
            var out: [Any] = []
            for e in arr { out.append(contentsOf: htmlSelect(selector, from: e)) }
            return out
        }
        return []
    }

    private func xpathSelect(_ path: String, from item: Any) -> [Any] {
        guard let node = item as? HTMLNode else {
            if let str = item as? String {
                return xpathSelect(path, from: HTMLParser.parse(str))
            }
            return []
        }
        let r = XPathLite.select(path, in: node)
        if let attr = r.attr {
            return r.nodes.compactMap { $0.attr(attr) }
        }
        if r.textOnly {
            return r.nodes.map { $0.textContent.trimmed() }
        }
        return r.nodes
    }

    private func jsonSelect(_ path: String, from item: Any) -> [Any] {
        var obj = item
        if let str = item as? String, let data = str.data(using: .utf8),
           let parsed = try? JSONSerialization.jsonObject(with: data) {
            obj = parsed
        }
        return JSONPathLite.query(obj, path: path)
    }

    private func regexSelect(_ expr: String, from item: Any) -> [Any] {
        let text = plainString(item)
        guard let v = regexFirst(expr, in: text) else { return [] }
        return [v]
    }

    // MARK: 工具

    private func regexFirst(_ pattern: String, in text: String) -> String? {
        var p = pattern
        var group = 1
        if let hashRange = p.range(of: "##") {
            let g = String(p[hashRange.upperBound...])
            p = String(p[..<hashRange.lowerBound])
            if let n = Int(g) { group = n }
        }
        guard let re = try? NSRegularExpression(pattern: p, options: [.dotMatchesLineSeparators]) else { return nil }
        let ns = text as NSString
        guard let m = re.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) else { return nil }
        if m.numberOfRanges > group, m.range(at: group).location != NSNotFound {
            return ns.substring(with: m.range(at: group))
        }
        return nil
    }

    private func applyReplacers(_ items: [Any], _ pairs: [(String, String)]) -> [Any] {
        items.map { item -> Any in
            guard let s = item as? String else { return item }
            var out = s
            for (pattern, replacement) in pairs {
                guard let re = try? NSRegularExpression(pattern: pattern, options: [.dotMatchesLineSeparators]) else { continue }
                let range = NSRange(location: 0, length: (out as NSString).length)
                out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: replacement)
            }
            return out
        }
    }

    private func substituteVariables(_ rule: String) -> String {
        var out = rule
        var all = variables
        all["baseUrl"] = baseUrl
        for (k, v) in all {
            out = out.replacingOccurrences(of: "{{\(k)}}", with: v)
        }
        return out
    }

    private func jsBindings() -> [String: Any] {
        var b: [String: Any] = ["baseUrl": baseUrl]
        for (k, v) in variables { b[k] = v }
        return b
    }

    private func firstString(_ values: [Any]) -> String {
        for v in values {
            let s = plainString(v).trimmed()
            if !s.isEmpty { return s }
        }
        return ""
    }

    func plainString(_ value: Any) -> String {
        if let s = value as? String { return s }
        if let n = value as? HTMLNode { return n.textContent }
        if let d = value as? [String: Any] {
            if let data = try? JSONSerialization.data(withJSONObject: d),
               let s = String(data: data, encoding: .utf8) { return s }
            return ""
        }
        if let a = value as? [Any] {
            return a.map { plainString($0) }.joined()
        }
        if let n = value as? NSNumber { return n.stringValue }
        return "\(value)"
    }

    // MARK: 静态拆分

    static func extractJS(_ s: String) -> (String, [String]) {
        var out = s
        var codes: [String] = []
        while let start = out.range(of: "{{"), let end = out.range(of: "}}", range: start.upperBound..<out.endIndex) {
            let code = String(out[start.upperBound..<end.lowerBound])
            out.replaceSubrange(start.lowerBound..<end.upperBound, with: "\u{1}\(codes.count)\u{1}")
            codes.append(code)
        }
        return (out, codes)
    }

    static func splitTop(_ s: String, _ sep: String) -> [String] {
        guard s.contains(sep) else { return [s] }
        return s.components(separatedBy: sep)
    }

    static func splitRegex(_ s: String) -> (String, [(String, String)]) {
        guard s.contains("##") else { return (s, []) }
        let parts = s.components(separatedBy: "##")
        var pairs: [(String, String)] = []
        var i = 1
        while i < parts.count {
            let pattern = parts[i]
            let replacement = (i + 1 < parts.count) ? parts[i + 1] : ""
            if !pattern.isEmpty { pairs.append((pattern, replacement)) }
            i += 2
        }
        return (parts[0], pairs)
    }
}

// MARK: - 小工具

extension String {
    func trimmed() -> String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func removingPrefixAny(_ prefixes: [String]) -> String? {
        for p in prefixes where hasPrefix(p) {
            return String(dropFirst(p.count))
        }
        return nil
    }

    /// 去掉 HTML 标签，保留纯文本
    func strippingHTML() -> String {
        guard contains("<") else { return self }
        var out = self
        let patterns = ["<script[^>]*>[\\s\\S]*?</script>",
                        "<style[^>]*>[\\s\\S]*?</style>",
                        "<br\\s*/?>",
                        "</p>",
                        "<[^>]+>"]
        for p in patterns {
            if let re = try? NSRegularExpression(pattern: p, options: [.caseInsensitive, .dotMatchesLineSeparators]) {
                let range = NSRange(location: 0, length: (out as NSString).length)
                let template = (p == "<br\\s*/?>" || p == "</p>") ? "\n" : ""
                out = re.stringByReplacingMatches(in: out, options: [], range: range, withTemplate: template)
            }
        }
        return HTMLParser.decodeEntities(out).trimmed()
    }

    /// 规整正文：统一换行、去除多余空行与广告行
    func normalizedText() -> String {
        var lines = components(separatedBy: "\n").map { $0.trimmed() }
        lines = lines.filter { line in
            if line.isEmpty { return true }
            if line.count <= 2 { return false }
            let junk = ["本章未完", "请记住本站", "最新章节", "手机用户请浏览", "笔趣阁", "https://", "http://", "www."]
            for j in junk where line.contains(j) && line.count < 60 { return false }
            return true
        }
        var out: [String] = []
        var blank = 0
        for line in lines {
            if line.isEmpty {
                blank += 1
                if blank > 1 { continue }
            } else {
                blank = 0
            }
            out.append(line)
        }
        return out.joined(separator: "\n").trimmed()
    }
}
