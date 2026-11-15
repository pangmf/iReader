//
//  HTMLParser.swift
//  WeReadLike
//
//  轻量 HTML 解析 + CSS 选择器 / 简化 XPath / JSONPath
//  不依赖任何第三方库，纯 Foundation 实现。
//

import Foundation

// MARK: - 节点

final class HTMLNode {
    var tag: String
    var attributes: [String: String]
    var children: [HTMLNode] = []
    weak var parent: HTMLNode?
    var text: String
    var isText: Bool

    init(tag: String, attributes: [String: String] = [:], text: String = "", isText: Bool = false) {
        self.tag = tag
        self.attributes = attributes
        self.text = text
        self.isText = isText
    }

    var outerHTML: String {
        if isText { return text }
        var s = "<\(tag)"
        for (k, v) in attributes { s += " \(k)=\"\(v)\"" }
        s += ">"
        for c in children { s += c.outerHTML }
        s += "</\(tag)>"
        return s
    }

    /// 所有后代文本（跳过 script / style）
    var textContent: String {
        if isText { return text }
        if tag == "script" || tag == "style" { return "" }
        var s = ""
        for c in children { s += c.textContent }
        return s
    }

    /// 直接子文本节点
    var ownText: String {
        children.filter { $0.isText }.map { $0.text }.joined()
    }

    func attr(_ name: String) -> String? {
        attributes[name.lowercased()]
    }

    func descendants() -> [HTMLNode] {
        var out: [HTMLNode] = []
        for c in children {
            out.append(c)
            out.append(contentsOf: c.descendants())
        }
        return out
    }
}

// MARK: - 解析器

enum HTMLParser {

    static let voidTags: Set<String> = [
        "area", "base", "br", "col", "embed", "hr", "img", "input",
        "link", "meta", "param", "source", "track", "wbr"
    ]

    static func parse(_ html: String) -> HTMLNode {
        let src = html as NSString
        let len = src.length
        var i = 0
        let root = HTMLNode(tag: "#root")
        var stack: [HTMLNode] = [root]

        func isSpace(_ c: unichar) -> Bool {
            c == 32 || c == 9 || c == 10 || c == 13 || c == 12
        }
        func isNameChar(_ c: unichar) -> Bool {
            (c >= 48 && c <= 57) || (c >= 65 && c <= 90) || (c >= 97 && c <= 122)
                || c == 45 || c == 58 || c == 95
        }
        func findGT(from start: Int) -> Int? {
            var j = start
            while j < len {
                let c = src.character(at: j)
                if c == 62 { return j }
                if c == 34 || c == 39 {
                    let quote = c
                    j += 1
                    while j < len && src.character(at: j) != quote { j += 1 }
                }
                j += 1
            }
            return nil
        }
        func closeTag(_ name: String) {
            var idx = stack.count - 1
            while idx > 0 {
                if stack[idx].tag == name {
                    stack.removeSubrange(idx...)
                    return
                }
                idx -= 1
            }
        }

        while i < len {
            let c = src.character(at: i)

            if c != 60 {
                // 文本
                var j = i
                while j < len && src.character(at: j) != 60 { j += 1 }
                let raw = src.substring(with: NSRange(location: i, length: j - i))
                let decoded = decodeEntities(raw)
                if !decoded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    let node = HTMLNode(tag: "#text", text: decoded, isText: true)
                    node.parent = stack[stack.count - 1]
                    stack[stack.count - 1].children.append(node)
                }
                i = j
                continue
            }

            // '<'
            guard i + 1 < len else { break }
            let c2 = src.character(at: i + 1)

            if c2 == 33 || c2 == 63 { // <!-- --> / <!DOCTYPE> / <?
                if let end = findGT(from: i) { i = end + 1 } else { break }
                continue
            }

            if c2 == 47 { // </tag>
                if let end = findGT(from: i) {
                    var name = src.substring(with: NSRange(location: i + 2, length: end - i - 2))
                    name = name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
                    if let sp = name.firstIndex(where: { $0 == " " || $0 == "\n" || $0 == "\t" }) {
                        name = String(name[..<sp])
                    }
                    closeTag(name)
                    i = end + 1
                } else { break }
                continue
            }

            // 开标签
            var j = i + 1
            var tagName = ""
            while j < len {
                let ch = src.character(at: j)
                if isNameChar(ch) {
                    tagName.append(Character(UnicodeScalar(ch)!))
                    j += 1
                } else { break }
            }
            if tagName.isEmpty {
                // 不是标签，当文本
                i += 1
                continue
            }
            tagName = tagName.lowercased()

            var attrs: [String: String] = [:]
            var selfClosing = false

            while j < len {
                while j < len && isSpace(src.character(at: j)) { j += 1 }
                if j >= len { break }
                let ch = src.character(at: j)
                if ch == 62 { j += 1; break }
                if ch == 47 { selfClosing = true; j += 1; continue }

                var aname = ""
                while j < len {
                    let cc = src.character(at: j)
                    if cc == 61 || cc == 62 || cc == 47 || isSpace(cc) { break }
                    aname.append(Character(UnicodeScalar(cc)!))
                    j += 1
                }
                while j < len && isSpace(src.character(at: j)) { j += 1 }

                var value = ""
                if j < len && src.character(at: j) == 61 {
                    j += 1
                    while j < len && isSpace(src.character(at: j)) { j += 1 }
                    if j < len {
                        let q = src.character(at: j)
                        if q == 34 || q == 39 {
                            j += 1
                            let start = j
                            while j < len && src.character(at: j) != q { j += 1 }
                            value = src.substring(with: NSRange(location: start, length: j - start))
                            if j < len { j += 1 }
                        } else {
                            let start = j
                            while j < len {
                                let cc = src.character(at: j)
                                if isSpace(cc) || cc == 62 { break }
                                j += 1
                            }
                            value = src.substring(with: NSRange(location: start, length: j - start))
                        }
                    }
                }
                if !aname.isEmpty {
                    attrs[aname.lowercased()] = decodeEntities(value)
                }
            }

            // p / li / td 等标签常常省略闭合，遇到同名标签时先把前一个闭合
            let autoClose: Set<String> = ["p", "li", "td", "tr", "th", "option", "dt", "dd", "h1", "h2", "h3", "h4"]
            if autoClose.contains(tagName), stack.count > 1, stack[stack.count - 1].tag == tagName {
                stack.removeLast()
            }

            let node = HTMLNode(tag: tagName, attributes: attrs)
            node.parent = stack[stack.count - 1]
            stack[stack.count - 1].children.append(node)

            // script / style 内部按原文吞掉，避免里面的 "<" 破坏结构
            if tagName == "script" || tagName == "style" {
                let searchRange = NSRange(location: j, length: max(0, len - j))
                let closeStr = "</" + tagName
                let r = src.range(of: closeStr, options: [.caseInsensitive], range: searchRange)
                if r.location != NSNotFound {
                    if r.location > j {
                        let raw = src.substring(with: NSRange(location: j, length: r.location - j))
                        let textNode = HTMLNode(tag: "#text", text: raw, isText: true)
                        textNode.parent = node
                        node.children.append(textNode)
                    }
                    let gt = src.range(of: ">", options: [], range: NSRange(location: r.location, length: max(0, len - r.location)))
                    i = (gt.location != NSNotFound) ? gt.location + 1 : len
                } else {
                    i = j
                }
                continue
            }

            if !selfClosing && !voidTags.contains(tagName) {
                stack.append(node)
            }
            i = j
        }

        return root
    }

    // MARK: 实体

    static func decodeEntities(_ s: String) -> String {
        guard s.contains("&") else { return s }
        var result = s
        let map: [String: String] = [
            "&amp;": "&", "&lt;": "<", "&gt;": ">", "&quot;": "\"",
            "&#39;": "'", "&apos;": "'", "&nbsp;": " ", "&mdash;": "—",
            "&ndash;": "–", "&hellip;": "…", "&ldquo;": "“", "&rdquo;": "”"
        ]
        for (k, v) in map { result = result.replacingOccurrences(of: k, with: v) }

        // 数字实体
        if result.contains("&#") {
            var out = ""
            var idx = result.startIndex
            while idx < result.endIndex {
                if result[idx] == "&", result.index(after: idx) < result.endIndex, result[result.index(after: idx)] == "#" {
                    if let semi = result[result.index(idx, offsetBy: 2)...].firstIndex(of: ";") {
                        let numStr = String(result[result.index(idx, offsetBy: 2)..<semi])
                        var scalar: UnicodeScalar?
                        if numStr.hasPrefix("x") || numStr.hasPrefix("X") {
                            if let v = UInt32(numStr.dropFirst(), radix: 16) { scalar = UnicodeScalar(v) }
                        } else if let v = UInt32(numStr) {
                            scalar = UnicodeScalar(v)
                        }
                        if let sc = scalar {
                            out.append(Character(sc))
                            idx = result.index(after: semi)
                            continue
                        }
                    }
                }
                out.append(result[idx])
                idx = result.index(after: idx)
            }
            result = out
        }
        return result
    }
}

// MARK: - CSS 选择器

struct CompoundSelector {
    var tag: String? = nil
    var id: String? = nil
    var classes: [String] = []
    var attrs: [(name: String, op: String, value: String)] = []
    var firstChild: Bool = false
    var lastChild: Bool = false
    var nthChild: Int? = nil
    var notClasses: [String] = []
}

enum CSSSelector {

    static func parse(_ selector: String) -> [(combinator: Character, compound: CompoundSelector)] {
        var result: [(combinator: Character, compound: CompoundSelector)] = []
        var current = ""
        var combinator: Character = " "
        var depth = 0
        var pendingCombinator: Character? = nil

        func flush(_ comb: Character) {
            let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                result.append((comb, parseCompound(trimmed)))
            }
            current = ""
        }

        var chars = Array(selector)
        var i = 0
        while i < chars.count {
            let ch = chars[i]
            if ch == "[" || ch == "(" {
                depth += 1
                current.append(ch)
            } else if ch == "]" || ch == ")" {
                depth -= 1
                current.append(ch)
            } else if depth == 0 && (ch == ">" || ch == "+" || ch == "~") {
                flush(pendingCombinator ?? combinator)
                pendingCombinator = ch
            } else if depth == 0 && (ch == " " || ch == "\n" || ch == "\t") {
                if !current.trimmingCharacters(in: .whitespaces).isEmpty {
                    flush(pendingCombinator ?? combinator)
                    pendingCombinator = nil
                    combinator = " "
                }
            } else {
                if pendingCombinator != nil { combinator = pendingCombinator!; pendingCombinator = nil }
                current.append(ch)
            }
            i += 1
        }
        flush(pendingCombinator ?? combinator)
        if !result.isEmpty { result[0].combinator = " " }
        return result
    }

    static func parseCompound(_ s: String) -> CompoundSelector {
        var c = CompoundSelector()
        var i = s.startIndex
        let end = s.endIndex

        // tag
        var tag = ""
        while i < end {
            let ch = s[i]
            if ch == "." || ch == "#" || ch == "[" || ch == ":" { break }
            tag.append(ch)
            i = s.index(after: i)
        }
        if !tag.isEmpty && tag != "*" { c.tag = tag.lowercased() }

        while i < end {
            let ch = s[i]
            if ch == "." {
                i = s.index(after: i)
                var name = ""
                while i < end && s[i] != "." && s[i] != "#" && s[i] != "[" && s[i] != ":" {
                    name.append(s[i]); i = s.index(after: i)
                }
                c.classes.append(name)
            } else if ch == "#" {
                i = s.index(after: i)
                var name = ""
                while i < end && s[i] != "." && s[i] != "#" && s[i] != "[" && s[i] != ":" {
                    name.append(s[i]); i = s.index(after: i)
                }
                c.id = name
            } else if ch == "[" {
                i = s.index(after: i)
                var body = ""
                while i < end && s[i] != "]" {
                    body.append(s[i]); i = s.index(after: i)
                }
                if i < end { i = s.index(after: i) }
                let trimmed = body.trimmingCharacters(in: .whitespaces)
                if let range = trimmed.range(of: "*=") {
                    c.attrs.append((String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                                    "*=",
                                    unquote(String(trimmed[range.upperBound...]))))
                } else if let range = trimmed.range(of: "^=") {
                    c.attrs.append((String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                                    "^=",
                                    unquote(String(trimmed[range.upperBound...]))))
                } else if let range = trimmed.range(of: "$=") {
                    c.attrs.append((String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                                    "$=",
                                    unquote(String(trimmed[range.upperBound...]))))
                } else if let range = trimmed.range(of: "=") {
                    c.attrs.append((String(trimmed[..<range.lowerBound]).trimmingCharacters(in: .whitespaces),
                                    "=",
                                    unquote(String(trimmed[range.upperBound...]))))
                } else {
                    c.attrs.append((trimmed, "", ""))
                }
            } else if ch == ":" {
                i = s.index(after: i)
                var name = ""
                while i < end && s[i] != ":" && s[i] != "." && s[i] != "[" && s[i] != ")" && s[i] != "(" {
                    name.append(s[i]); i = s.index(after: i)
                }
                if name.hasPrefix("first-child") { c.firstChild = true }
                else if name.hasPrefix("last-child") { c.lastChild = true }
                else if name.hasPrefix("nth-child") {
                    if i < end && s[i] == "(" {
                        i = s.index(after: i)
                        var num = ""
                        while i < end && s[i] != ")" { num.append(s[i]); i = s.index(after: i) }
                        if i < end { i = s.index(after: i) }
                        if let n = Int(num.trimmingCharacters(in: .whitespaces)) { c.nthChild = n }
                    }
                } else if name.hasPrefix("not") {
                    if i < end && s[i] == "(" {
                        i = s.index(after: i)
                        var body = ""
                        var d = 1
                        while i < end {
                            if s[i] == ")" { d -= 1; if d == 0 { break } }
                            if s[i] == "(" { d += 1 }
                            body.append(s[i]); i = s.index(after: i)
                        }
                        if i < end { i = s.index(after: i) }
                        let inner = body.trimmingCharacters(in: .whitespaces)
                        if inner.hasPrefix(".") { c.notClasses.append(String(inner.dropFirst())) }
                    }
                }
            } else {
                i = s.index(after: i)
            }
        }
        return c
    }

    private static func unquote(_ s: String) -> String {
        var v = s.trimmingCharacters(in: .whitespaces)
        if v.count >= 2, (v.hasPrefix("\"") && v.hasSuffix("\"")) || (v.hasPrefix("'") && v.hasSuffix("'")) {
            v = String(v.dropFirst().dropLast())
        }
        return v
    }

    static func matches(_ node: HTMLNode, _ c: CompoundSelector) -> Bool {
        if node.isText { return false }
        if let t = c.tag, node.tag != t { return false }
        if let id = c.id, node.attr("id") != id { return false }
        if !c.classes.isEmpty {
            let nodeClasses = (node.attr("class") ?? "").split(separator: " ").map { String($0) }
            for cls in c.classes where !nodeClasses.contains(cls) { return false }
        }
        for cls in c.notClasses {
            let nodeClasses = (node.attr("class") ?? "").split(separator: " ").map { String($0) }
            if nodeClasses.contains(cls) { return false }
        }
        for a in c.attrs {
            guard let v = node.attr(a.name) else { return false }
            switch a.op {
            case "=": if v != a.value { return false }
            case "*=": if !v.contains(a.value) { return false }
            case "^=": if !v.hasPrefix(a.value) { return false }
            case "$=": if !v.hasSuffix(a.value) { return false }
            default: break
            }
        }
        if c.firstChild || c.lastChild || c.nthChild != nil {
            guard let parent = node.parent else { return false }
            let siblings = parent.children.filter { !$0.isText }
            guard let idx = siblings.firstIndex(where: { $0 === node }) else { return false }
            if c.firstChild && idx != 0 { return false }
            if c.lastChild && idx != siblings.count - 1 { return false }
            if let n = c.nthChild, idx + 1 != n { return false }
        }
        return true
    }

    static func select(_ selector: String, in root: HTMLNode) -> [HTMLNode] {
        var all: [HTMLNode] = []
        for group in selector.components(separatedBy: ",") {
            let groups = group.trimmingCharacters(in: .whitespaces)
            if groups.isEmpty { continue }
            all.append(contentsOf: run(groups, in: root))
        }
        return all
    }

    private static func run(_ selector: String, in root: HTMLNode) -> [HTMLNode] {
        let steps = parse(selector)
        guard !steps.isEmpty else { return [] }

        var current: [HTMLNode] = []
        for c in root.children where !c.isText {
            if matches(c, steps[0].compound) { current.append(c) }
            collectDeep(c, steps[0].compound, into: &current)
        }
        if current.isEmpty { return [] }

        for step in steps.dropFirst() {
            var next: [HTMLNode] = []
            switch step.combinator {
            case ">":
                for node in current {
                    for child in node.children where !child.isText {
                        if matches(child, step.compound) { next.append(child) }
                    }
                }
            case "+":
                for node in current {
                    guard let p = node.parent,
                          let idx = p.children.firstIndex(where: { $0 === node }),
                          idx + 1 < p.children.count else { continue }
                    let sibling = p.children[idx + 1]
                    if !sibling.isText && matches(sibling, step.compound) { next.append(sibling) }
                }
            case "~":
                for node in current {
                    guard let p = node.parent,
                          let idx = p.children.firstIndex(where: { $0 === node }) else { continue }
                    for k in (idx + 1)..<p.children.count {
                        let s = p.children[k]
                        if !s.isText && matches(s, step.compound) { next.append(s) }
                    }
                }
            default:
                for node in current {
                    for child in node.children where !child.isText {
                        if matches(child, step.compound) { next.append(child) }
                        collectDeep(child, step.compound, into: &next)
                    }
                }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
    }

    private static func collectDeep(_ node: HTMLNode, _ c: CompoundSelector, into out: inout [HTMLNode]) {
        for child in node.children where !child.isText {
            if matches(child, c) { out.append(child) }
            collectDeep(child, c, into: &out)
        }
    }
}

// MARK: - 简化 XPath

enum XPathLite {

    struct Step {
        var descendant: Bool
        var expr: String
    }

    static func parse(_ path: String) -> [Step] {
        var steps: [Step] = []
        let chars = Array(path)
        var i = 0
        while i < chars.count {
            if chars[i] == "/" {
                var descendant = false
                if i + 1 < chars.count && chars[i + 1] == "/" {
                    descendant = true
                    i += 2
                } else {
                    i += 1
                }
                var buf = ""
                var depth = 0
                while i < chars.count {
                    let ch = chars[i]
                    if ch == "[" { depth += 1 }
                    if ch == "]" { depth -= 1 }
                    if ch == "/" && depth == 0 { break }
                    buf.append(ch)
                    i += 1
                }
                let e = buf.trimmingCharacters(in: .whitespaces)
                if !e.isEmpty { steps.append(Step(descendant: descendant, expr: e)) }
            } else {
                i += 1
            }
        }
        return steps
    }

    static func select(_ path: String, in root: HTMLNode) -> (nodes: [HTMLNode], attr: String?, textOnly: Bool) {
        let steps = parse(path)
        var current: [HTMLNode] = [root]
        var attr: String? = nil
        var textOnly = false

        for step in steps {
            var e = step.expr
            if e == "text()" { textOnly = true; continue }
            if e.hasPrefix("@") { attr = String(e.dropFirst()); continue }

            var tag = e
            var predicate = ""
            if let b = e.firstIndex(of: "[") {
                tag = String(e[..<b])
                predicate = String(e[b...])
                predicate = predicate.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            }
            var index: Int? = nil
            if let n = Int(predicate), n > 0 { index = n }

            var attrCond: (String, String)? = nil
            if predicate.hasPrefix("@"), let eq = predicate.firstIndex(of: "=") {
                let name = String(predicate[predicate.index(after: predicate.startIndex)..<eq]).trimmingCharacters(in: .whitespaces)
                var value = String(predicate[predicate.index(after: eq)...]).trimmingCharacters(in: .whitespaces)
                if (value.hasPrefix("\"") && value.hasSuffix("\"")) || (value.hasPrefix("'") && value.hasSuffix("'")) {
                    value = String(value.dropFirst().dropLast())
                }
                attrCond = (name, value)
            }
            let containsCond: (String, String)? = {
                guard predicate.hasPrefix("contains(@") else { return nil }
                guard let comma = predicate.range(of: ",") else { return nil }
                let namePart = String(predicate[predicate.index(predicate.startIndex, offsetBy: 10)..<comma.lowerBound])
                var value = String(predicate[comma.upperBound...]).trimmingCharacters(in: CharacterSet(charactersIn: " )'\""))
                value = value.trimmingCharacters(in: .whitespaces)
                return (namePart.trimmingCharacters(in: .whitespaces), value)
            }()

            var next: [HTMLNode] = []
            for node in current {
                var pool: [HTMLNode] = []
                if step.descendant {
                    pool = node.descendants().filter { !$0.isText }
                } else {
                    pool = node.children.filter { !$0.isText }
                }
                var filtered = pool.filter { n in
                    if tag != "*" && !tag.isEmpty && n.tag != tag.lowercased() { return false }
                    if let (an, av) = attrCond, n.attr(an) != av { return false }
                    if let (an, av) = containsCond, !(n.attr(an) ?? "").contains(av) { return false }
                    return true
                }
                if let idx = index, idx <= filtered.count {
                    filtered = [filtered[idx - 1]]
                }
                next.append(contentsOf: filtered)
            }
            current = next
            if current.isEmpty { break }
        }
        return (current, attr, textOnly)
    }
}

// MARK: - JSONPath（子集）

enum JSONPathLite {

    static func query(_ object: Any, path: String) -> [Any] {
        var p = path.trimmingCharacters(in: .whitespaces)
        if p.hasPrefix("$..") {
            p = "." + String(p.dropFirst(3))
        } else if p.hasPrefix("$") {
            p = String(p.dropFirst())
        }

        var segments: [String] = []
        var buf = ""
        var i = p.startIndex
        while i < p.endIndex {
            let ch = p[i]
            if ch == "." {
                if !buf.isEmpty { segments.append(buf); buf = "" }
            } else if ch == "[" {
                if !buf.isEmpty { segments.append(buf); buf = "" }
                var inner = ""
                var j = p.index(after: i)
                while j < p.endIndex && p[j] != "]" {
                    inner.append(p[j]); j = p.index(after: j)
                }
                segments.append("[" + inner + "]")
                i = j < p.endIndex ? p.index(after: j) : p.endIndex
                continue
            } else {
                buf.append(ch)
            }
            i = p.index(after: i)
        }
        if !buf.isEmpty { segments.append(buf) }

        var current: [Any] = [object]
        for seg in segments {
            var next: [Any] = []
            if seg.hasPrefix("[") {
                let inner = String(seg.dropFirst().dropLast()).trimmingCharacters(in: .whitespaces)
                if inner == "*" {
                    for item in current {
                        if let arr = item as? [Any] { next.append(contentsOf: arr) }
                        else if let dict = item as? [String: Any] { next.append(contentsOf: dict.values) }
                    }
                } else if let idx = Int(inner) {
                    for item in current {
                        if let arr = item as? [Any], idx < arr.count, idx >= 0 { next.append(arr[idx]) }
                    }
                } else {
                    let key = inner.trimmingCharacters(in: CharacterSet(charactersIn: "'\""))
                    for item in current {
                        if let dict = item as? [String: Any], let v = dict[key] { next.append(v) }
                    }
                }
            } else if seg == "*" {
                for item in current {
                    if let arr = item as? [Any] { next.append(contentsOf: arr) }
                    else if let dict = item as? [String: Any] { next.append(contentsOf: dict.values) }
                }
            } else {
                for item in current {
                    if let dict = item as? [String: Any], let v = dict[seg] { next.append(v) }
                }
            }
            current = next
            if current.isEmpty { return [] }
        }
        return current
    }
}
