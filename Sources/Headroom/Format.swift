import Foundation

enum Fmt {
    /// "claude-opus-5-5" → "Opus 5.5", "gpt-6.1-sol" → "GPT-6.1 Sol".
    static func model(_ id: String) -> String {
        var s = id.lowercased()
        for prefix in ["anthropic/", "openai/", "google/", "models/"] where s.hasPrefix(prefix) {
            s.removeFirst(prefix.count)
        }
        if s.hasPrefix("claude-") {
            let parts = s.dropFirst("claude-".count).split(separator: "-")
            guard let family = parts.first else { return id }
            let version = parts.dropFirst().prefix { $0.allSatisfy(\.isNumber) && $0.count <= 2 }
            let name = family.prefix(1).uppercased() + family.dropFirst()
            return version.isEmpty ? name : "\(name) \(version.joined(separator: "."))"
        }
        if s.hasPrefix("gpt-") {
            let parts = s.dropFirst(4).split(separator: "-")
            guard let v = parts.first else { return id }
            let rest = parts.dropFirst().map { $0.prefix(1).uppercased() + $0.dropFirst() }
            return (["GPT-\(v)"] + rest).joined(separator: " ")
        }
        return s.split(separator: "-").map { part -> String in
            part.first?.isNumber == true ? String(part) : part.prefix(1).uppercased() + part.dropFirst()
        }.joined(separator: " ")
    }

    static func client(_ id: String) -> String {
        switch id.lowercased() {
        case "claude": return "Claude Code"
        case "codex": return "Codex"
        case "antigravity", "antigravity-cli", "antigravity-extension": return "Antigravity"
        case "cursor": return "Cursor"
        case "gemini": return "Gemini CLI"
        case "opencode": return "OpenCode"
        case "grok": return "Grok"
        case "copilot": return "Copilot"
        default: return id.prefix(1).uppercased() + id.dropFirst()
        }
    }

    static func money(_ v: Double) -> String {
        if v >= 1000 { return String(format: "$%.0f", v) }
        if v >= 100 { return String(format: "$%.1f", v) }
        return String(format: "$%.2f", v)
    }

    static func tokens(_ n: Int) -> String {
        let d = Double(n)
        switch d {
        case 1e9...: return String(format: "%.2fB", d / 1e9)
        case 1e6...: return String(format: "%.1fM", d / 1e6)
        case 1e3...: return String(format: "%.1fK", d / 1e3)
        default: return "\(n)"
        }
    }

    /// Whole numbers with a comma every three digits: "2,744".
    static func count(_ n: Int) -> String {
        let f = NumberFormatter()
        f.numberStyle = .decimal
        f.locale = Locale(identifier: "en_US")
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func percent(_ v: Double) -> String {
        if v > 0 && v < 1 { return String(format: "%.1f%%", v) }
        // Nearest whole percent, the same as `tokscale usage --light`.
        return "\(Int(v.rounded()))%"
    }

    /// "2h 05m", "14m", "45s".
    static func duration(_ t: TimeInterval) -> String {
        let s = Int(max(0, t))
        let d = s / 86400, h = (s % 86400) / 3600, m = (s % 3600) / 60
        if d > 0 { return "\(d)d \(h)h" }
        if h > 0 { return "\(h)h \(String(format: "%02d", m))m" }
        if m > 0 { return "\(m)m" }
        return "\(s)s"
    }

    /// Rough, friendly duration for forecasts: "about 3h", "about 40m".
    static func about(_ t: TimeInterval) -> String {
        if t >= 2 * 86400 { return "about \(Int((t / 86400).rounded()))d" }
        if t >= 3600 { return "about \(Int((t / 3600).rounded()))h" }
        return "about \(max(1, Int((t / 60).rounded())))m"
    }

    /// Reset time: "3h 12m" when close, "Fri 3 PM" further out.
    static func reset(_ date: Date, now: Date) -> String {
        let t = date.timeIntervalSince(now)
        if t <= 0 { return "now" }
        if t < 20 * 3600 { return duration(t) }
        return resetFormatter.string(from: date)
    }

    static func age(_ date: Date?, now: Date) -> String {
        guard let date else { return "never" }
        let t = now.timeIntervalSince(date)
        if t < 10 { return "just now" }
        if t < 60 { return "\(Int(t))s ago" }
        return duration(t) + " ago"
    }

    static func clock(_ date: Date) -> String { clockFormatter.string(from: date) }

    private static let resetFormatter: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEE j")
        return f
    }()

    private static let clockFormatter: DateFormatter = {
        let f = DateFormatter()
        f.timeStyle = .short
        return f
    }()
}

/// Two-letter provider marks. Plain letters, never brand logos.
enum Monogram {
    static func letters(_ provider: String) -> String {
        switch provider.lowercased() {
        case "claude", "claude code": return "Cl"
        case "codex": return "Cx"
        case "antigravity", "antigravity-cli", "antigravity-extension": return "Ag"
        case "cursor": return "Cu"
        case "gemini", "gemini cli": return "Ge"
        case "grok": return "Gk"
        case "copilot": return "Co"
        case "opencode": return "Oc"
        default: return String(provider.prefix(2)).capitalized
        }
    }
}
