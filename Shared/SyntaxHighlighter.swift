import Foundation

enum FileFormat {
    case json, yaml, toml, xml, mobileconfig

    init?(pathExtension: String) {
        switch pathExtension.lowercased() {
        case "json": self = .json
        case "yaml", "yml": self = .yaml
        case "toml": self = .toml
        case "xml": self = .xml
        case "mobileconfig", "plist": self = .mobileconfig
        default: return nil
        }
    }
}

enum SyntaxHighlighter {
    static func highlight(_ source: String, format: FileFormat) -> String {
        if format == .mobileconfig, let data = source.data(using: .utf8) {
            if let html = renderMobileconfig(data) {
                return html
            }
        }
        let tokens: [Token]
        switch format {
        case .json: tokens = tokenizeJSON(source)
        case .yaml: tokens = tokenizeYAML(source)
        case .toml: tokens = tokenizeTOML(source)
        case .xml, .mobileconfig: tokens = tokenizeXML(source)
        }
        return wrapHTML(renderTokens(tokens))
    }

    // MARK: - Mobileconfig Renderer

    private static func renderMobileconfig(_ data: Data) -> String? {
        guard let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        var html = ""

        // Profile header
        let displayName = plist["PayloadDisplayName"] as? String ?? "Untitled Profile"
        let identifier = plist["PayloadIdentifier"] as? String ?? ""
        let payloads = plist["PayloadContent"] as? [[String: Any]] ?? []

        // Collect actual payload types (the useful info)
        let payloadTypes = payloads.compactMap { $0["PayloadType"] as? String }

        html += "<div class=\"profile-header\">"
        html += "<div class=\"profile-name\">\(escapeHTML(displayName))</div>"
        if !identifier.isEmpty {
            html += "<div class=\"profile-id\">\(escapeHTML(identifier))</div>"
        }
        if !payloadTypes.isEmpty {
            html += "<div class=\"profile-meta\">"
            for pt in payloadTypes {
                html += "<span class=\"badge\">\(escapeHTML(pt))</span>"
            }
            html += "</div>"
        }
        html += "</div>"

        // Top-level settings (excluding payload metadata and PayloadContent)
        let metaKeys: Set = ["PayloadType", "PayloadVersion", "PayloadUUID", "PayloadIdentifier",
                             "PayloadDisplayName", "PayloadContent", "PayloadDescription",
                             "PayloadOrganization", "PayloadScope", "PayloadRemovalDisallowed"]
        let topSettings = plist.filter { !metaKeys.contains($0.key) }
        if !topSettings.isEmpty {
            html += renderSettingsTable(topSettings, title: nil)
        }

        // Payload content
        for payload in payloads {
            let name = payload["PayloadDisplayName"] as? String
                ?? payload["PayloadType"] as? String
                ?? "Payload"
            let type = payload["PayloadType"] as? String ?? ""

            html += "<div class=\"payload-section\">"
            html += "<div class=\"payload-header\">"
            html += "<div class=\"payload-name\">\(escapeHTML(name))</div>"
            if !type.isEmpty {
                html += "<div class=\"payload-type\">\(escapeHTML(type))</div>"
            }
            html += "</div>"

            let settings = payload.filter { !metaKeys.contains($0.key) }
            if !settings.isEmpty {
                html += renderSettingsTable(settings, title: nil)
            }
            html += "</div>"
        }

        return wrapMobileconfigHTML(html, rawXML: String(data: data, encoding: .utf8) ?? "")
    }

    private static func renderSettingsTable(_ settings: [String: Any], title: String?) -> String {
        var html = ""
        if let title = title {
            html += "<div class=\"section-title\">\(escapeHTML(title))</div>"
        }
        html += "<table>"
        for key in settings.keys.sorted() {
            let value = settings[key]!
            html += "<tr>"
            html += "<td class=\"setting-key\">\(escapeHTML(key))</td>"
            html += "<td class=\"setting-value\">\(renderValue(value))</td>"
            html += "</tr>"
        }
        html += "</table>"
        return html
    }

    private static func renderValue(_ value: Any, depth: Int = 0) -> String {
        switch value {
        case let bool as Bool:
            return "<span class=\"val-bool\">\(bool ? "true" : "false")</span>"
        case let num as NSNumber:
            return "<span class=\"val-num\">\(num)</span>"
        case let str as String:
            return "<span class=\"val-str\">\(escapeHTML(str))</span>"
        case let arr as [Any]:
            if arr.isEmpty { return "<span class=\"val-empty\">[ ]</span>" }
            let items = arr.map { "<li>\(renderValue($0, depth: depth + 1))</li>" }.joined()
            return "<ul>\(items)</ul>"
        case let dict as [String: Any]:
            if dict.isEmpty { return "<span class=\"val-empty\">{ }</span>" }
            var html = "<table class=\"nested\">"
            for key in dict.keys.sorted() {
                html += "<tr><td class=\"setting-key\">\(escapeHTML(key))</td>"
                html += "<td class=\"setting-value\">\(renderValue(dict[key]!, depth: depth + 1))</td></tr>"
            }
            html += "</table>"
            return html
        case let data as Data:
            return "<span class=\"val-str\">\(data.count) bytes</span>"
        default:
            return "<span class=\"val-str\">\(escapeHTML(String(describing: value)))</span>"
        }
    }

    private static func wrapMobileconfigHTML(_ body: String, rawXML: String) -> String {
        let xmlTokens = tokenizeXML(rawXML)
        let highlightedXML = renderTokens(xmlTokens)
        return """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root { color-scheme: light dark; }
        * { box-sizing: border-box; }
        body {
            font: 13px/1.5 -apple-system, "SF Pro Text", Helvetica, sans-serif;
            margin: 0; padding: 20px;
            background: #ffffff; color: #1d1d1f;
        }
        .toggle-bar { display: flex; gap: 0; margin-bottom: 16px; }
        .toggle-btn {
            font: 12px/1 -apple-system, sans-serif; font-weight: 600;
            padding: 6px 14px; border: 1px solid #d1d1d6; background: #fff;
            color: #1d1d1f; cursor: pointer;
        }
        .toggle-btn:first-child { border-radius: 6px 0 0 6px; }
        .toggle-btn:last-child { border-radius: 0 6px 6px 0; border-left: 0; }
        .toggle-btn.active { background: #0071e3; color: #fff; border-color: #0071e3; }
        .profile-header {
            padding: 16px 20px; margin-bottom: 16px;
            background: #f5f5f7; border-radius: 10px;
        }
        .profile-name { font-size: 18px; font-weight: 700; }
        .profile-id { font-size: 12px; color: #86868b; font-family: ui-monospace, monospace; margin-top: 2px; }
        .profile-meta { margin-top: 8px; display: flex; gap: 6px; flex-wrap: wrap; }
        .badge {
            font-size: 11px; font-weight: 600; padding: 2px 8px;
            background: #0071e3; color: #fff; border-radius: 4px;
        }
        .payload-section { margin-bottom: 16px; }
        .payload-header {
            padding: 10px 16px; background: #f5f5f7; border-radius: 8px 8px 0 0;
            border-bottom: 1px solid #e5e5ea;
        }
        .payload-name { font-size: 14px; font-weight: 600; }
        .payload-type { font-size: 11px; color: #86868b; font-family: ui-monospace, monospace; }
        table { width: 100%; border-collapse: collapse; }
        tr { border-bottom: 1px solid #f0f0f0; }
        td { padding: 6px 12px; vertical-align: top; }
        .setting-key {
            width: 40%; font-weight: 500; color: #1d1d1f;
            font-family: ui-monospace, monospace; font-size: 12px;
        }
        .setting-value { font-size: 12px; }
        .val-bool { color: #0071e3; font-weight: 600; }
        .val-num { color: #bf5af2; font-weight: 600; }
        .val-str { color: #1d1d1f; }
        .val-empty { color: #86868b; }
        ul { margin: 0; padding-left: 16px; }
        table.nested { margin: 2px 0; }
        table.nested td { padding: 3px 8px; }
        #xml-view {
            display: none;
            font: 13px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
            white-space: pre-wrap; word-wrap: break-word;
        }
        .key       { color: #0451a5; }
        .string    { color: #a31515; }
        .number    { color: #098658; }
        .bool      { color: #0000ff; }
        .comment   { color: #6a9955; font-style: italic; }
        .tag       { color: #800000; }
        .attrName  { color: #e50000; }
        .attrValue { color: #0451a5; }
        .plistKey  { color: #0451a5; font-weight: bold; }
        .plistValue { color: #a31515; font-weight: bold; }
        @media (prefers-color-scheme: dark) {
            body { background: #1e1e1e; color: #d4d4d4; }
            .toggle-btn { background: #2a2a2c; color: #d4d4d4; border-color: #3a3a3c; }
            .toggle-btn.active { background: #0a84ff; color: #fff; border-color: #0a84ff; }
            .profile-header, .payload-header { background: #2a2a2c; }
            .profile-id, .payload-type { color: #98989d; }
            .badge { background: #0a84ff; }
            tr { border-bottom-color: #2a2a2c; }
            .setting-key { color: #d4d4d4; }
            .val-bool { color: #0a84ff; }
            .val-num { color: #bf5af2; }
            .val-str { color: #d4d4d4; }
            .val-empty { color: #98989d; }
            .key       { color: #9cdcfe; }
            .string    { color: #ce9178; }
            .tag       { color: #569cd6; }
            .attrName  { color: #9cdcfe; }
            .attrValue { color: #ce9178; }
            .plistKey  { color: #9cdcfe; font-weight: bold; }
            .plistValue { color: #ce9178; font-weight: bold; }
            .comment   { color: #6a9955; }
        }
        </style>
        </head>
        <body>
        <div class="toggle-bar">
            <button class="toggle-btn active" onclick="showView('structured')">Profile</button>
            <button class="toggle-btn" onclick="showView('xml')">XML</button>
        </div>
        <div id="structured-view">\(body)</div>
        <div id="xml-view">\(highlightedXML)</div>
        <script>
        function showView(view) {
            document.getElementById('structured-view').style.display = view === 'structured' ? 'block' : 'none';
            document.getElementById('xml-view').style.display = view === 'xml' ? 'block' : 'none';
            document.querySelectorAll('.toggle-btn').forEach(function(btn) {
                btn.classList.toggle('active', btn.textContent === (view === 'structured' ? 'Profile' : 'XML'));
            });
        }
        </script>
        </body>
        </html>
        """
    }

    // MARK: - Token

    private struct Token {
        enum Kind: String {
            case plain, key, string, number, bool, comment, tag, attrName, attrValue, punctuation, plistKey, plistValue
        }
        let text: String
        let kind: Kind
    }

    // MARK: - JSON Tokenizer

    private static func tokenizeJSON(_ src: String) -> [Token] {
        let regex = try! Regex(#"("(?:[^"\\]|\\.)*")\s*(:)|("(?:[^"\\]|\\.)*")|\b(-?\d+(?:\.\d+)?(?:[eE][+-]?\d+)?)\b|\b(true|false|null)\b"#)
        return tokenize(src, regex: regex) { match in
            if let key = match[1], match[2] != nil {
                return [Token(text: key, kind: .key), Token(text: ":", kind: .punctuation)]
            } else if let str = match[3] {
                return [Token(text: str, kind: .string)]
            } else if let num = match[4] {
                return [Token(text: num, kind: .number)]
            } else if let b = match[5] {
                return [Token(text: b, kind: .bool)]
            }
            return nil
        }
    }

    // MARK: - YAML Tokenizer

    private static func tokenizeYAML(_ src: String) -> [Token] {
        let regex = try! Regex(#"(?m)(#.*)$|^([\t ]*(?:- )?[A-Za-z_][\w.\-/]*)\s*(:)|("(?:[^"\\]|\\.)*"|'[^']*')|\b(true|false|yes|no|null|~)\b|\b(-?\d+(?:\.\d+)?)\b"#)
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let key = match[2], match[3] != nil {
                return [Token(text: key, kind: .key), Token(text: ":", kind: .punctuation)]
            } else if let str = match[4] {
                return [Token(text: str, kind: .string)]
            } else if let b = match[5] {
                return [Token(text: b, kind: .bool)]
            } else if let num = match[6] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - TOML Tokenizer

    private static func tokenizeTOML(_ src: String) -> [Token] {
        let regex = try! Regex(#"(?m)(#.*)$|(\[{1,2}[^\]]*\]{1,2})|^([\t ]*[A-Za-z_][\w.\-]*)\s*(=)|("(?:[^"\\]|\\.)*"|'[^']*'|"""[\s\S]*?"""|'''[\s\S]*?''')|\b(true|false)\b|\b(\d{4}-\d{2}-\d{2}(?:T\d{2}:\d{2}:\d{2})?)\b|\b(-?\d+(?:\.\d+)?)\b"#)
        return tokenize(src, regex: regex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let header = match[2] {
                return [Token(text: header, kind: .tag)]
            } else if let key = match[3], match[4] != nil {
                return [Token(text: key, kind: .key), Token(text: "=", kind: .punctuation)]
            } else if let str = match[5] {
                return [Token(text: str, kind: .string)]
            } else if let b = match[6] {
                return [Token(text: b, kind: .bool)]
            } else if let date = match[7] {
                return [Token(text: date, kind: .attrValue)]
            } else if let num = match[8] {
                return [Token(text: num, kind: .number)]
            }
            return nil
        }
    }

    // MARK: - XML Tokenizer

    private static func tokenizeXML(_ src: String) -> [Token] {
        // Match Payload key+value pairs, then general XML
        let mainRegex = try! Regex(
            #"(<!--[\s\S]*?-->)"# +        // 1: comment
            #"|(<!\[CDATA\[[\s\S]*?\]\]>)"# + // 2: CDATA
            #"|(<key>)(Payload\w+)(</key>\s*)(<(?:string|integer)>)([^<]*)(</(?:string|integer)>)"# + // 3-8: Payload key + value
            #"|(<key>)(Payload\w+)(</key>)"# + // 9-11: Payload key without simple value
            #"|(<\/?[A-Za-z_][\w:\-.]*)(\s[^>]*)?(\/?>)"# + // 12-14: general tag
            #"|("[^"]*"|'[^']*')"#          // 15: quoted string
        ).dotMatchesNewlines()
        return tokenize(src, regex: mainRegex) { match in
            if let comment = match[1] {
                return [Token(text: comment, kind: .comment)]
            } else if let cdata = match[2] {
                return [Token(text: cdata, kind: .string)]
            } else if let open = match[3], let keyText = match[4], let mid = match[5],
                      let valOpen = match[6], let valText = match[7], let valClose = match[8] {
                // <key>PayloadIdentifier</key>\n<string>value</string> → both bold
                return [
                    Token(text: open, kind: .tag),
                    Token(text: keyText, kind: .plistKey),
                    Token(text: mid, kind: .tag),
                    Token(text: valOpen, kind: .tag),
                    Token(text: valText, kind: .plistValue),
                    Token(text: valClose, kind: .tag),
                ]
            } else if let open = match[9], let keyText = match[10], let close = match[11] {
                // <key>PayloadContent</key> (followed by array/dict, not simple value)
                return [
                    Token(text: open, kind: .tag),
                    Token(text: keyText, kind: .plistKey),
                    Token(text: close, kind: .tag),
                ]
            } else if let tagName = match[12] {
                var result = [Token(text: tagName, kind: .tag)]
                if let attrs = match[13] {
                    result.append(contentsOf: tokenizeXMLAttributes(attrs))
                }
                if let close = match[14] {
                    result.append(Token(text: close, kind: .tag))
                }
                return result
            } else if let str = match[15] {
                return [Token(text: str, kind: .attrValue)]
            }
            return nil
        }
    }

    private static func tokenizeXMLAttributes(_ attrs: String) -> [Token] {
        let regex = try! Regex(#"([A-Za-z_][\w:\-.]*)(\s*=\s*)("[^"]*"|'[^']*')"#)
        return tokenize(attrs, regex: regex) { match in
            if let name = match[1], let eq = match[2], let value = match[3] {
                return [
                    Token(text: name, kind: .attrName),
                    Token(text: eq, kind: .plain),
                    Token(text: value, kind: .attrValue),
                ]
            }
            return nil
        }
    }

    // MARK: - Regex Engine

    private static func tokenize(
        _ src: String,
        regex: Regex<AnyRegexOutput>,
        handler: (MatchResult) -> [Token]?
    ) -> [Token] {
        var tokens: [Token] = []
        var searchStart = src.startIndex

        while let match = try? regex.firstMatch(in: src[searchStart...]) {
            if match.range.lowerBound > searchStart {
                tokens.append(Token(text: String(src[searchStart..<match.range.lowerBound]), kind: .plain))
            }

            let result = MatchResult(match: match)
            if let produced = handler(result) {
                tokens.append(contentsOf: produced)
            } else {
                tokens.append(Token(text: String(src[match.range]), kind: .plain))
            }
            searchStart = match.range.upperBound
        }

        if searchStart < src.endIndex {
            tokens.append(Token(text: String(src[searchStart...]), kind: .plain))
        }

        return tokens
    }

    private struct MatchResult {
        let match: Regex<AnyRegexOutput>.Match

        subscript(index: Int) -> String? {
            guard index < match.output.count else { return nil }
            guard let substring = match.output[index].substring else { return nil }
            return String(substring)
        }
    }

    // MARK: - HTML Rendering

    private static func renderTokens(_ tokens: [Token]) -> String {
        tokens.map { token in
            let escaped = escapeHTML(token.text)
            switch token.kind {
            case .plain, .punctuation:
                return escaped
            default:
                return "<span class=\"\(token.kind.rawValue)\">\(escaped)</span>"
            }
        }.joined()
    }

    private static func escapeHTML(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }

    private static func wrapHTML(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <style>
        :root {
            color-scheme: light dark;
        }
        body {
            font: 13px/1.5 ui-monospace, "SF Mono", Menlo, monospace;
            margin: 0;
            padding: 16px 20px;
            background: #ffffff;
            color: #1d1d1f;
            -webkit-text-size-adjust: none;
        }
        pre {
            margin: 0;
            white-space: pre-wrap;
            word-wrap: break-word;
        }
        .key       { color: #0451a5; }
        .string    { color: #a31515; }
        .number    { color: #098658; }
        .bool      { color: #0000ff; }
        .comment   { color: #6a9955; font-style: italic; }
        .tag       { color: #800000; }
        .attrName  { color: #e50000; }
        .attrValue { color: #0451a5; }
        .plistKey  { color: #0451a5; font-weight: bold; }
        .plistValue { color: #a31515; font-weight: bold; }
        @media (prefers-color-scheme: dark) {
            body {
                background: #1e1e1e;
                color: #d4d4d4;
            }
            .key       { color: #9cdcfe; }
            .string    { color: #ce9178; }
            .number    { color: #b5cea8; }
            .bool      { color: #569cd6; }
            .comment   { color: #6a9955; }
            .tag       { color: #569cd6; }
            .attrName  { color: #9cdcfe; }
            .attrValue { color: #ce9178; }
            .plistKey  { color: #9cdcfe; font-weight: bold; }
            .plistValue { color: #ce9178; font-weight: bold; }
        }
        </style>
        </head>
        <body><pre>\(body)</pre></body>
        </html>
        """
    }
}
