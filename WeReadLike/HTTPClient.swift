//
//  HTTPClient.swift
//  WeReadLike
//
//  网络层：GET/POST、自动编码识别（UTF-8 / GBK / GB18030）、Cookie 透传
//

import Foundation
import CoreFoundation

final class HTTPClient {

    static let shared = HTTPClient()

    private let session: URLSession
    private var cookieJar: [String: [HTTPCookie]] = [:]
    private let lock = NSLock()

    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        config.httpAdditionalHeaders = [
            "User-Agent": "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
            "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
            "Accept-Language": "zh-CN,zh;q=0.9"
        ]
        session = URLSession(configuration: config)
    }

    struct Response {
        var body: String
        var finalUrl: String
        var statusCode: Int
    }

    func fetch(url: String,
               method: String = "GET",
               body: String? = nil,
               headers: [String: String] = [:],
               referer: String? = nil) async throws -> Response {

        var target = url
        if target.unicodeScalars.contains(where: { $0.value > 127 }) {
            target = target.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? url
        }
        guard let u = URL(string: target) ?? URL(string: url) else {
            throw NSError(domain: "HTTPClient", code: -1,
                          userInfo: [NSLocalizedDescriptionKey: "无效链接"])
        }

        var request = URLRequest(url: u)
        request.httpMethod = method
        request.setValue("Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.0 Mobile/15E148 Safari/604.1",
                         forHTTPHeaderField: "User-Agent")
        if let referer = referer { request.setValue(referer, forHTTPHeaderField: "Referer") }
        for (k, v) in headers { request.setValue(v, forHTTPHeaderField: k) }
        if let body = body {
            request.httpBody = body.data(using: .utf8)
            if request.value(forHTTPHeaderField: "Content-Type") == nil {
                request.setValue("application/x-www-form-urlencoded; charset=UTF-8",
                                 forHTTPHeaderField: "Content-Type")
            }
        }
        if let host = u.host, let cookies = storedCookies(for: host) {
            for (k, v) in HTTPCookie.requestHeaderFields(with: cookies) {
                request.setValue(v, forHTTPHeaderField: k)
            }
        }

        let (data, response) = try await session.data(for: request)
        let http = response as? HTTPURLResponse
        if let http = http, let host = u.host {
            saveCookies(http, for: host)
        }

        let text = Self.decode(data: data, response: http)
        return Response(body: text,
                        finalUrl: http?.url?.absoluteString ?? url,
                        statusCode: http?.statusCode ?? 0)
    }

    // MARK: 编码识别

    static func decode(data: Data, response: HTTPURLResponse?) -> String {
        if let charset = response?.textEncodingName,
           let enc = encoding(for: charset),
           let s = String(data: data, encoding: enc) {
            return s
        }
        if let s = String(data: data, encoding: .utf8) { return s }

        // 从 HTML meta 中提取 charset
        let head = String(data: data.prefix(2048), encoding: .isoLatin1) ?? ""
        if let r = head.range(of: "charset=", options: .caseInsensitive) {
            let rest = head[r.upperBound...].prefix(24)
            let name = rest.components(separatedBy: CharacterSet(charactersIn: "\"' />;\n\r")).first ?? ""
            if let enc = encoding(for: name), let s = String(data: data, encoding: enc) { return s }
        }

        if let s = String(data: data, encoding: .gb_18030_2000) { return s }
        if let s = String(data: data, encoding: .isoLatin1) { return s }
        return ""
    }

    static func encoding(for name: String) -> String.Encoding? {
        let n = name.lowercased().trimmed()
        switch n {
        case "utf-8", "utf8": return .utf8
        case "gbk", "gb2312", "gb-2312", "gb18030", "gb-18030": return .gb_18030_2000
        case "big5", "big-5": return .big5
        case "iso-8859-1", "latin1": return .isoLatin1
        default:
            let cf = CFStringConvertIANACharSetNameToEncoding(n as CFString)
            if cf != kCFStringEncodingInvalidId {
                return String.Encoding(rawValue: CFStringConvertEncodingToNSStringEncoding(cf))
            }
            return nil
        }
    }

    // MARK: Cookie

    private func storedCookies(for host: String) -> [HTTPCookie]? {
        lock.lock(); defer { lock.unlock() }
        return cookieJar[host]
    }

    private func saveCookies(_ response: HTTPURLResponse, for host: String) {
        guard let url = response.url else { return }
        let newCookies = HTTPCookie.cookies(withResponseHeaderFields: response.allHeaderFields as? [String: String] ?? [:],
                                            for: url)
        guard !newCookies.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        var list = cookieJar[host] ?? []
        for c in newCookies {
            list.removeAll { $0.name == c.name }
            list.append(c)
        }
        cookieJar[host] = list
    }

    func cookiesHeader(for url: String) -> String {
        guard let host = URL(string: url)?.host, let cookies = storedCookies(for: host) else { return "" }
        return cookies.map { "\($0.name)=\($0.value)" }.joined(separator: "; ")
    }
}

extension String.Encoding {
    static var gb_18030_2000: String.Encoding {
        let cf = CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
        return String.Encoding(rawValue: cf)
    }
}
