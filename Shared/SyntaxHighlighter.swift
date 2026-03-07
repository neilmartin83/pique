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

    private static let payloadMetaKeys: Set<String> = [
        "PayloadType", "PayloadVersion", "PayloadUUID", "PayloadIdentifier",
        "PayloadDisplayName", "PayloadDescription",
        "PayloadOrganization", "PayloadScope", "PayloadRemovalDisallowed",
        "PayloadEnabled"
    ]

    /// Extract effective settings, flattening ManagedClient.preferences nesting
    private static func extractSettings(_ payload: [String: Any]) -> [String: Any] {
        let type = payload["PayloadType"] as? String ?? ""
        if type == "com.apple.ManagedClient.preferences",
           let content = payload["PayloadContent"] as? [String: Any] {
            for (_, domainVal) in content {
                if let domain = domainVal as? [String: Any],
                   let forced = domain["Forced"] as? [[String: Any]],
                   let first = forced.first,
                   let mcx = first["mcx_preference_settings"] as? [String: Any] {
                    return mcx
                }
            }
            return content
        }
        return payload.filter { !payloadMetaKeys.contains($0.key) && $0.key != "PayloadContent" }
    }

    /// Check if a value is simple (renders inline) vs complex (needs its own block)
    private static func isSimple(_ value: Any) -> Bool {
        switch value {
        case is Bool, is NSNumber: return true
        case let s as String: return s.count < 120
        case let a as [Any]: return a.isEmpty
        case let d as [String: Any]: return d.isEmpty
        default: return true
        }
    }

    /// Check if a string value is "long" (should span full width)
    private static func isLongString(_ value: Any) -> Bool {
        if let s = value as? String { return s.count > 60 }
        return false
    }

    // MARK: - Mobileconfig Renderer (HIG-style inset grouped)

    // Tailwind-inspired design tokens
    private static let pad = 16
    private static let groupBg = "#f8fafc"   // slate-50
    private static let cellBg = "#ffffff"
    private static let sepColor = "#e2e8f0"  // slate-200 (light, crisp)
    private static let keyColor = "#334155"   // slate-700
    private static let labelColor = "#64748b" // slate-500
    private static let mutedColor = "#94a3b8"  // slate-400
    private static let accentColor = "#6366f1" // indigo-500

    private static func renderMobileconfig(_ data: Data) -> String? {
        guard let rawXML = String(data: data, encoding: .utf8),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            return nil
        }

        var h = ""  // html accumulator

        let displayName = plist["PayloadDisplayName"] as? String ?? "Untitled Profile"
        let identifier = plist["PayloadIdentifier"] as? String ?? ""
        let org = plist["PayloadOrganization"] as? String
        let desc = plist["PayloadDescription"] as? String
        let scope = plist["PayloadScope"] as? String
        let payloads = plist["PayloadContent"] as? [[String: Any]] ?? []
        let payloadTypes = payloads.compactMap { $0["PayloadType"] as? String }

        // ── Profile Header ──
        let scopeText: String
        let scopeColor: String
        switch scope {
        case "System": scopeText = "Device Profile"; scopeColor = "#ea580c"  // orange-600
        case "User":   scopeText = "User Profile";   scopeColor = "#2563eb"  // blue-600
        default:       scopeText = "Profile";         scopeColor = mutedColor
        }

        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(cellBg)\"><tr><td style=\"padding: 20px \(pad)px 16px \(pad)px;\">"
        h += "<font color=\"\(scopeColor)\" size=\"1\"><b>\(scopeText.uppercased())</b></font><br>"
        h += "<font size=\"5\" face=\"-apple-system, Helvetica\" color=\"#0f172a\"><b>\(esc(displayName))</b></font>"
        if let org = org { h += "<br><font size=\"2\" color=\"\(labelColor)\">\(esc(org))</font>" }
        h += "<br><font size=\"1\" face=\"Menlo\" color=\"\(mutedColor)\">\(esc(identifier))</font>"
        if let desc = desc, !desc.isEmpty {
            h += "<br><font size=\"2\" color=\"\(labelColor)\">\(esc(desc))</font>"
        }

        // Payload type badges inline
        if !payloadTypes.isEmpty {
            h += "<br><br>"
            for pt in payloadTypes {
                let short = pt.split(separator: ".").last.map(String.init) ?? pt
                h += "<font size=\"1\" face=\"Menlo\" color=\"\(accentColor)\"><b>\(esc(short))</b></font>"
                h += "<font color=\"\(mutedColor)\"> &middot; </font>"
            }
        }

        h += "</td></tr></table>"

        // ── Payload Sections ──
        for (idx, payload) in payloads.enumerated() {
            let name = payload["PayloadDisplayName"] as? String
                ?? payload["PayloadType"] as? String ?? "Payload"
            let type = payload["PayloadType"] as? String ?? ""
            let payloadDesc = payload["PayloadDescription"] as? String

            // Payload header bar
            h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
            h += "<tr><td colspan=\"2\" style=\"padding: 28px \(pad)px 0 \(pad)px;\"><table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(sepColor)\" style=\"font-size:1px; line-height:1px; height:1px;\">&nbsp;</td></tr></table></td></tr>"
            h += "<tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
            h += "<font size=\"1\" color=\"\(mutedColor)\"><b>PAYLOAD \(idx + 1)</b></font><br>"
            h += "<font size=\"3\" face=\"-apple-system, Helvetica\" color=\"#1e293b\"><b>\(esc(name))</b></font>"
            if !type.isEmpty && type != name {
                h += "<br><font size=\"1\" face=\"Menlo\" color=\"\(mutedColor)\">\(esc(type))</font>"
            }
            if let d = payloadDesc, !d.isEmpty {
                h += "<br><font size=\"2\" color=\"\(labelColor)\">\(esc(d))</font>"
            }
            h += "</td></tr></table>"

            let settings = extractSettings(payload)
            guard !settings.isEmpty else { continue }

            // Split simple vs complex
            let sorted = settings.keys.sorted()
            let simpleKeys = sorted.filter { isSimple(settings[$0]!) }
            let complexKeys = sorted.filter { !isSimple(settings[$0]!) }

            // ── Simple settings group (HIG inset grouped table) ──
            if !simpleKeys.isEmpty {
                h += groupStart()
                for (i, key) in simpleKeys.enumerated() {
                    h += cellRow(key, inlineValue(settings[key]!, key: key), last: i == simpleKeys.count - 1)
                }
                h += groupEnd()
            }

            // ── Complex settings: each gets its own group ──
            for key in complexKeys {
                h += sectionHeader(key)
                h += renderComplexValue(settings[key]!)
            }
        }

        // ── XML Source ──
        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\">"
        h += "<tr><td style=\"padding: 28px \(pad)px 0 \(pad)px;\"><table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(sepColor)\" style=\"font-size:1px; line-height:1px; height:1px;\">&nbsp;</td></tr></table></td></tr>"
        h += "<tr><td style=\"padding: 8px \(pad)px 6px \(pad)px;\">"
        h += "<font size=\"1\" color=\"\(mutedColor)\"><b>XML SOURCE</b></font>"
        h += "</td></tr></table>"

        h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(cellBg)\" style=\"padding: 12px \(pad)px;\">"
        let xmlTokens = tokenizeXML(rawXML)
        h += "<pre style=\"font: 11px/1.6 Menlo, monospace; margin: 0; white-space: pre-wrap; word-wrap: break-word; color: \(keyColor);\">\(renderTokens(xmlTokens))</pre>"
        h += "</td></tr></table>"

        return wrapMobileconfigHTML(h)
    }

    // MARK: - HIG Table Building Blocks

    /// Section header: uppercase label above a group
    private static func sectionHeader(_ title: String) -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 16px \(pad)px 6px \(pad)px;\">" +
        "<font size=\"1\" color=\"\(labelColor)\"><b>\(esc(title).uppercased())</b></font>" +
        "</td></tr></table>"
    }

    /// Start a white inset group
    private static func groupStart() -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\" bgcolor=\"\(cellBg)\">"
    }

    /// End a group
    private static func groupEnd() -> String { "</table>" }

    /// Thin 1px separator row (no <hr> — NSAttributedString renders those as fat bars)
    private static func thinSep() -> String {
        "<tr><td colspan=\"2\" style=\"padding: 0 0 0 \(pad)px;\"><table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(sepColor)\" style=\"font-size:1px; line-height:1px; height:1px;\">&nbsp;</td></tr></table></td></tr>"
    }

    /// Inline 1px separator (for use inside an existing <td>)
    private static func thinSepInline() -> String {
        "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td bgcolor=\"\(sepColor)\" style=\"font-size:1px; line-height:1px; height:1px;\">&nbsp;</td></tr></table>"
    }

    /// A single cell row: key on left, value on right, with bottom separator unless last
    private static func cellRow(_ key: String, _ value: String, last: Bool = false) -> String {
        var r = "<tr bgcolor=\"\(cellBg)\"><td valign=\"top\" style=\"padding: 9px \(pad)px; width: 38%;\">"
        r += "<font size=\"2\" color=\"\(keyColor)\">\(esc(key))</font></td>"
        r += "<td valign=\"top\" style=\"padding: 9px \(pad)px;\">\(value)</td></tr>"
        if !last { r += thinSep() }
        return r
    }

    /// Keys whose integer values represent hours
    private static let hourKeys: Set<String> = [
        "gracePeriodInstallDelay", "gracePeriodLaunchDelay"
    ]

    /// Heuristic: does this key name suggest a time/duration value?
    private static func isTimeKey(_ key: String) -> Bool {
        let lower = key.lowercased()
        let timeWords = ["time", "cycle", "delay", "interval", "timeout", "duration", "period", "refresh", "expir"]
        return timeWords.contains { lower.contains($0) }
    }

    /// Format seconds into "Xd Xh Xm Xs"
    private static func formatDuration(seconds: Int) -> String {
        if seconds == 0 { return "0s" }
        let d = seconds / 86400
        let h = (seconds % 86400) / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        if m > 0 { parts.append("\(m)m") }
        if s > 0 { parts.append("\(s)s") }
        return parts.joined(separator: " ")
    }

    /// Format hours into "Xd Xh"
    private static func formatHours(_ hours: Int) -> String {
        if hours == 0 { return "0h" }
        let d = hours / 24
        let h = hours % 24
        var parts: [String] = []
        if d > 0 { parts.append("\(d)d") }
        if h > 0 { parts.append("\(h)h") }
        return parts.joined(separator: " ")
    }

    /// Render a simple/inline value, optionally with time annotation for known keys
    private static func inlineValue(_ value: Any, key: String? = nil) -> String {
        switch value {
        case let bool as Bool:
            let color = bool ? "#059669" : "#dc2626"  // emerald-600 / red-600
            return "<font size=\"2\" color=\"\(color)\"><b>\(bool ? "Yes" : "No")</b></font>"
        case let num as NSNumber:
            var result = "<font size=\"2\" color=\"\(accentColor)\"><b>\(num)</b></font>"
            if let key = key, num.intValue > 0 {
                if hourKeys.contains(key) {
                    result += " <font size=\"1\" color=\"\(mutedColor)\">(\(formatHours(num.intValue)))</font>"
                } else if isTimeKey(key) {
                    result += " <font size=\"1\" color=\"\(mutedColor)\">(\(formatDuration(seconds: num.intValue)))</font>"
                }
            }
            return result
        case let str as String where str.isEmpty:
            return "<font size=\"2\" color=\"\(mutedColor)\"><i>—</i></font>"
        case let str as String:
            return "<font size=\"2\" color=\"#1e293b\">\(esc(str))</font>"  // slate-800
        default:
            return "<font size=\"2\" color=\"#1e293b\">\(esc(String(describing: value)))</font>"
        }
    }

    /// Render a complex value (dict, array of dicts) as its own group(s)
    private static func renderComplexValue(_ value: Any) -> String {
        var h = ""
        switch value {
        case let arr as [[String: Any]]:
            // Array of dicts: each dict is a numbered group
            for (i, dict) in arr.enumerated() {
                let label = dict["_language"] as? String
                    ?? dict["identifier"] as? String
                    ?? dict["BundleIdentifier"] as? String
                    ?? dict["Identifier"] as? String
                    ?? dict["RuleValue"] as? String
                    ?? nil
                if let label = label {
                    h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
                    h += "<font size=\"1\" color=\"\(labelColor)\">\(esc(label))</font>"
                    h += "</td></tr></table>"
                } else if arr.count > 1 {
                    h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 10px \(pad)px 4px \(pad)px;\">"
                    h += "<font size=\"1\" color=\"\(labelColor)\">Item \(i + 1)</font>"
                    h += "</td></tr></table>"
                }
                h += groupStart()
                let keys = dict.keys.sorted()
                for (j, key) in keys.enumerated() {
                    let val = dict[key]!
                    let isLast = j == keys.count - 1
                    if isSimple(val) && !isLongString(val) {
                        h += cellRow(key, inlineValue(val, key: key), last: isLast)
                    } else if isLongString(val) {
                        // Long string: key and value stacked full-width
                        h += "<tr bgcolor=\"\(cellBg)\"><td colspan=\"2\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(keyColor)\">\(esc(key))</font></td></tr>"
                        h += "<tr bgcolor=\"\(cellBg)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad)px;\">"
                        h += "<font size=\"1\" face=\"Menlo\" color=\"\(labelColor)\">\(esc(val as! String))</font></td></tr>"
                        if !isLast {
                            h += "<tr><td colspan=\"2\" style=\"padding: 0 0 0 \(pad)px;\">\(thinSepInline())</td></tr>"
                        }
                    } else {
                        // Complex nested value: key as label, value indented below
                        h += "<tr bgcolor=\"\(cellBg)\"><td colspan=\"2\" valign=\"top\" style=\"padding: 9px \(pad)px 3px \(pad)px;\">"
                        h += "<font size=\"2\" color=\"\(keyColor)\">\(esc(key))</font></td></tr>"
                        h += "<tr bgcolor=\"\(cellBg)\"><td colspan=\"2\" style=\"padding: 0 \(pad)px 9px \(pad + 8)px;\">"
                        h += renderNestedBlock(val)
                        h += "</td></tr>"
                        if !isLast {
                            h += "<tr><td colspan=\"2\" style=\"padding: 0 0 0 \(pad)px;\">\(thinSepInline())</td></tr>"
                        }
                    }
                }
                h += groupEnd()
            }

        case let arr as [Any]:
            // Array of simple values
            h += groupStart()
            for (i, item) in arr.enumerated() {
                h += cellRow("[\(i)]", inlineValue(item), last: i == arr.count - 1)
            }
            h += groupEnd()

        case let dict as [String: Any]:
            // Dict: split simple/complex like top level
            let keys = dict.keys.sorted()
            let simpleK = keys.filter { isSimple(dict[$0]!) }
            let complexK = keys.filter { !isSimple(dict[$0]!) }

            if !simpleK.isEmpty {
                h += groupStart()
                for (i, key) in simpleK.enumerated() {
                    h += cellRow(key, inlineValue(dict[key]!, key: key), last: i == simpleK.count - 1)
                }
                h += groupEnd()
            }
            for key in complexK {
                h += "<table width=\"100%\" cellpadding=\"0\" cellspacing=\"0\"><tr><td style=\"padding: 12px \(pad)px 4px \(pad)px;\">"
                h += "<font size=\"1\" color=\"\(labelColor)\"><b>\(esc(key).uppercased())</b></font>"
                h += "</td></tr></table>"
                h += renderComplexValue(dict[key]!)
            }

        default:
            h += groupStart()
            h += "<tr><td style=\"padding: 10px \(pad)px;\">\(inlineValue(value))</td></tr>"
            h += groupEnd()
        }
        return h
    }

    /// Render deeply nested content (inside a complex value cell)
    private static func renderNestedBlock(_ value: Any) -> String {
        switch value {
        case let arr as [[String: Any]]:
            var h = ""
            for (i, dict) in arr.enumerated() {
                if i > 0 { h += "<br>" }
                let label = dict["identifier"] as? String ?? dict["Identifier"] as? String
                if let label = label {
                    h += "<font size=\"1\" color=\"\(labelColor)\">\(esc(label))</font><br>"
                }
                for key in dict.keys.sorted() {
                    h += "<font size=\"1\" face=\"Menlo\" color=\"\(mutedColor)\">\(esc(key))</font> "
                    h += inlineValue(dict[key]!)
                    h += "<br>"
                }
            }
            return h
        case let arr as [Any]:
            return arr.map { inlineValue($0) }.joined(separator: ", ")
        case let dict as [String: Any]:
            var h = ""
            for key in dict.keys.sorted() {
                h += "<font size=\"1\" face=\"Menlo\" color=\"\(mutedColor)\">\(esc(key))</font> "
                if isSimple(dict[key]!) {
                    h += inlineValue(dict[key]!)
                } else {
                    h += renderNestedBlock(dict[key]!)
                }
                h += "<br>"
            }
            return h
        default:
            return inlineValue(value)
        }
    }

    /// Short alias for escapeHTML
    private static func esc(_ s: String) -> String { escapeHTML(s) }

    private static func wrapMobileconfigHTML(_ body: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8">
        <style>
        body {
            font: 13px/1.5 -apple-system, Helvetica, sans-serif;
            margin: 0; padding: 0;
            background: \(groupBg); color: #0f172a;
        }
        pre { margin: 0; }
        table { border-collapse: collapse; }
        .key       { color: #0451a5; }
        .string    { color: #c41a16; }
        .number    { color: #1c00cf; }
        .bool      { color: #0b4f79; }
        .comment   { color: #8e8e93; font-style: italic; }
        .tag       { color: #643820; }
        .attrName  { color: #5856d6; }
        .attrValue { color: #c41a16; }
        .plistKey  { color: #0451a5; font-weight: bold; }
        .plistValue { color: #c41a16; font-weight: bold; }
        </style>
        </head>
        <body>\(body)</body>
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
