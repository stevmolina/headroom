import Foundation

/// Recent quota readings, kept on disk so the burn rate survives a relaunch.
struct QuotaHistory: Codable {
    struct Sample: Codable, Equatable {
        var at: Date
        var used: Double
        var resetsAt: Date?
    }

    /// Samples per metric id, oldest first, about five minutes apart.
    var samples: [String: [Sample]] = [:]

    mutating func record(_ usage: [ProviderUsage], at: Date) {
        for card in usage {
            let id = card.provider + (card.account?.label.map { "/" + $0 } ?? "")
            for m in card.metrics {
                record(id: id + "#" + m.label, sample: Sample(at: at, used: m.usedPercent, resetsAt: m.resetsAt))
            }
        }
    }

    mutating func record(id: String, sample: Sample) {
        var list = samples[id] ?? []
        // Keep readings at least five minutes apart, plus the newest one: the
        // newest replaces the last entry until five minutes have passed since
        // the entry before it. Replacing on every 60 s poll would keep a
        // single reading and never build a trend.
        if list.count >= 2, sample.at.timeIntervalSince(list[list.count - 2].at) < 300 {
            list[list.count - 1] = sample
        } else {
            list.append(sample)
        }
        list.removeAll { sample.at.timeIntervalSince($0.at) > 6 * 3600 }
        samples[id] = list
    }

    private static var url: URL { AppPaths.support.appendingPathComponent("history.json") }

    static func load() -> QuotaHistory {
        guard let data = try? Data(contentsOf: url),
              let h = try? JSONDecoder().decode(QuotaHistory.self, from: data) else { return QuotaHistory() }
        return h
    }

    func save() {
        if let data = try? JSONEncoder().encode(self) { try? data.write(to: Self.url, options: .atomic) }
    }
}

enum Burn {
    /// The length of a quota window, guessed from its label. `nil` when unknown.
    static func windowLength(label: String) -> TimeInterval? {
        let l = label.lowercased()
        if l == "5h" || l == "session" || l.contains("5 hour") { return 5 * 3600 }
        if l.contains("week") || l == "fable" || l == "opus" || l == "sonnet" { return 7 * 86400 }
        if l.contains("day") || l == "24h" { return 86400 }
        if l.contains("month") { return 30 * 86400 }
        return nil
    }

    /// Percent of quota used per second, from what we have seen.
    ///
    /// Prefers the recent trend (a reading 15 to 90 minutes old in the same
    /// window). Falls back to the average pace since the window opened.
    static func rate(metricId: String, label: String, used: Double, resetsAt: Date?,
                     history: QuotaHistory, now: Date) -> Double? {
        if let past = history.samples[metricId]?.last(where: { s in
            let age = now.timeIntervalSince(s.at)
            return age >= 15 * 60 && age <= 90 * 60 && sameWindow(s.resetsAt, resetsAt)
        }) {
            let dt = now.timeIntervalSince(past.at)
            let du = used - past.used
            // Flat or falling in the same window: you are idle, so no forecast.
            return du > 0 ? du / dt : nil
        }

        guard let resetsAt, let window = windowLength(label: label) else { return nil }
        let elapsed = window - resetsAt.timeIntervalSince(now)
        // Early in a window one busy hour looks like a runaway pace; wait
        // until a tenth of the window (at least 30 minutes) has passed.
        guard elapsed > max(30 * 60, window * 0.1), used > 0 else { return nil }
        return used / elapsed
    }

    /// Time until the limit is used up, when that comes before the reset.
    static func runsOutIn(metricId: String, label: String, used: Double, resetsAt: Date?,
                          history: QuotaHistory, now: Date) -> TimeInterval? {
        let remaining = 100 - used
        guard remaining > 0.05, let resetsAt else { return nil }
        guard let r = rate(metricId: metricId, label: label, used: used, resetsAt: resetsAt,
                           history: history, now: now), r > 0 else { return nil }
        let toEmpty = remaining / r
        let toReset = resetsAt.timeIntervalSince(now)
        return toEmpty < toReset ? toEmpty : nil
    }

    private static func sameWindow(_ a: Date?, _ b: Date?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a.timeIntervalSince(b)) < 600
    }
}
