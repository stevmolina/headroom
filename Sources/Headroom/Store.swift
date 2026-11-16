import Foundation
import Observation
import SwiftUI

/// One quota bar: a provider (or Antigravity quota group) and one of its limits.
struct LimitRow: Identifiable, Hashable {
    var id: String
    var metric: String
    var remaining: Double
    var used: Double
    var resetsAt: Date?
    var runsOutIn: TimeInterval?
}

/// A provider block in the Limits section.
struct LimitGroup: Identifiable, Hashable {
    var id: String
    var provider: String
    var group: String?
    var plan: String?
    var rows: [LimitRow]

    var title: String {
        guard let group else { return provider }
        return "\(provider) · \(group)"
    }

    var lowest: Double { rows.map(\.remaining).min() ?? 100 }
}

enum Level {
    case normal, low, critical

    init(remaining: Double) {
        if remaining < 5 { self = .critical } else if remaining < 20 { self = .low } else { self = .normal }
    }
}

/// Keeps the latest tokscale readings, refreshes them off the main thread and
/// persists them so a relaunch shows the last numbers immediately.
@MainActor
@Observable
final class UsageStore {
    // Latest readings
    private(set) var usage: [ProviderUsage] = []
    private var sessionsSnapshot: [SessionRow] = []

    /// Today's sessions. A snapshot from an earlier day (a restored cache, or
    /// the app running past midnight) shows as empty until the next refresh.
    var sessions: [SessionRow] {
        guard let at = sessionsFetchedAt, Calendar.current.isDate(at, inSameDayAs: now) else { return [] }
        return sessionsSnapshot
    }
    private(set) var week: [GraphDay] = []

    private(set) var usageFetchedAt: Date?
    private(set) var sessionsFetchedAt: Date?
    private(set) var weekFetchedAt: Date?

    private(set) var isRefreshingUsage = false
    private(set) var isRefreshingSessions = false
    private(set) var usageError: String?
    private(set) var activityError: String?
    /// The error to show under the panel, newest source first.
    var lastError: String? { usageError ?? activityError }
    private(set) var tokscalePath: String?

    /// Ticks every few seconds so "updated 40s ago" and elapsed times stay live.
    private(set) var now = Date()

    var hiddenProviders: Set<String> {
        didSet { UserDefaults.standard.set(Array(hiddenProviders), forKey: "hiddenProviders") }
    }

    var tokscaleOverride: String {
        didSet {
            UserDefaults.standard.set(tokscaleOverride, forKey: "tokscalePath")
            resolveTokscale()
        }
    }

    private var tokscale: Tokscale?
    private var history = QuotaHistory()
    private var timers: [Timer] = []

    init() {
        hiddenProviders = Set(UserDefaults.standard.stringArray(forKey: "hiddenProviders") ?? [])
        tokscaleOverride = UserDefaults.standard.string(forKey: "tokscalePath") ?? ""
        resolveTokscale()
        loadCache()
        history = QuotaHistory.load()
    }

    func start() {
        guard timers.isEmpty else { return }
        refreshUsage()
        refreshActivity()
        timers.append(Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { _ in
            Task { @MainActor in self.refreshUsage() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 180, repeats: true) { _ in
            Task { @MainActor in self.refreshActivity() }
        })
        timers.append(Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            Task { @MainActor in self.now = Date() }
        })
    }

    /// Called when the panel opens: quota always, activity when it is stale.
    func panelOpened() {
        now = Date()
        refreshUsage()
        if (sessionsFetchedAt.map { now.timeIntervalSince($0) } ?? .infinity) > 30 {
            refreshActivity()
        }
    }

    func refreshAll() {
        refreshUsage()
        refreshActivity()
    }

    private func resolveTokscale() {
        tokscale = Tokscale.locate(override: tokscaleOverride)
        tokscalePath = tokscale?.executable.path
    }

    // MARK: - Refresh

    func refreshUsage() {
        guard !isRefreshingUsage else { return }
        if tokscale == nil { resolveTokscale() }  // installed after launch
        guard let tokscale else { usageError = Tokscale.Failure.notFound.errorDescription; return }
        isRefreshingUsage = true
        Task {
            defer { isRefreshingUsage = false }
            do {
                let fresh = try await tokscale.usage()
                let at = Date()
                withAnimation(.smooth(duration: 0.6)) {
                    usage = fresh
                    usageFetchedAt = at
                }
                history.record(fresh, at: at)
                history.save()
                usageError = nil
                saveCache()
            } catch {
                usageError = error.localizedDescription
            }
        }
    }

    func refreshActivity() {
        guard !isRefreshingSessions else { return }
        guard let tokscale else { return }
        isRefreshingSessions = true
        Task {
            defer { isRefreshingSessions = false }
            async let sessionsResult = capture { try await tokscale.sessionsToday() }
            async let weekResult = capture { try await tokscale.week() }
            let (s, w) = await (sessionsResult, weekResult)
            withAnimation(.smooth(duration: 0.6)) {
                if case .success(let report) = s {
                    sessionsSnapshot = report.sessions
                    sessionsFetchedAt = Date()
                }
                if case .success(let graph) = w {
                    week = graph.contributions
                    weekFetchedAt = Date()
                }
            }
            switch (s, w) {
            case (.failure(let e), _), (_, .failure(let e)): activityError = e.localizedDescription
            default: activityError = nil
            }
            saveCache()
        }
    }

    // MARK: - Derived: limits

    var limitGroups: [LimitGroup] {
        usage.map { card in
            let group = card.account?.label
            let id = card.provider + (group.map { "/" + $0 } ?? "")
            let rows = card.metrics.map { m -> LimitRow in
                let rowId = id + "#" + m.label
                return LimitRow(
                    id: rowId,
                    metric: displayMetric(m.label),
                    remaining: m.remainingPercent,
                    used: m.usedPercent,
                    resetsAt: m.resetsAt,
                    runsOutIn: forecast(rowId: rowId, metric: m)
                )
            }
            return LimitGroup(id: id, provider: card.provider, group: group, plan: card.plan, rows: rows)
        }
    }

    /// Forecast made at the moment of the reading, then counted down with the
    /// clock, so it does not drift while no new reading arrives.
    private func forecast(rowId: String, metric m: ProviderUsage.Metric) -> TimeInterval? {
        let at = usageFetchedAt ?? now
        guard let out = Burn.runsOutIn(metricId: rowId, label: m.label, used: m.usedPercent,
                                       resetsAt: m.resetsAt, history: history, now: at) else { return nil }
        let left = out - now.timeIntervalSince(at)
        return left > 0 ? left : nil
    }

    /// Provider names that can be toggled in Settings.
    var providerNames: [String] {
        var seen: [String] = []
        for g in limitGroups where !seen.contains(g.title) { seen.append(g.title) }
        return seen
    }

    /// The limit closest to running out across visible providers, for the pill.
    var tightest: (group: LimitGroup, row: LimitRow)? {
        var best: (LimitGroup, LimitRow)?
        for g in limitGroups where !hiddenProviders.contains(g.title) {
            for r in g.rows where best == nil || r.remaining < best!.1.remaining {
                best = (g, r)
            }
        }
        return best.map { (group: $0.0, row: $0.1) }
    }

    private func displayMetric(_ label: String) -> String {
        switch label.lowercased() {
        case "5h": return "5 hour"
        case "weekly": return "Weekly"
        default: return label.prefix(1).uppercased() + label.dropFirst()
        }
    }

    // MARK: - Derived: activity

    /// Sessions with a message in the last few minutes: agents working now.
    var liveSessions: [SessionRow] {
        sessions.filter { now.timeIntervalSince($0.lastActive) < 5 * 60 }
    }

    var today: GraphDay? {
        let key = Self.dayFormatter.string(from: now)
        return week.first { $0.date == key }
    }

    /// The last seven days, oldest first, with zero-cost days filled in.
    var weekSeries: [(date: Date, cost: Double)] {
        let cal = Calendar.current
        let byDate = Dictionary(week.map { ($0.date, $0.totals.cost) }, uniquingKeysWith: +)
        return (0..<7).reversed().compactMap { offset in
            guard let day = cal.date(byAdding: .day, value: -offset, to: cal.startOfDay(for: now)) else { return nil }
            return (day, byDate[Self.dayFormatter.string(from: day)] ?? 0)
        }
    }

    var topModelToday: (model: String, cost: Double)? {
        guard let today else { return nil }
        var costs: [String: Double] = [:]
        for c in today.clients { costs[c.modelId, default: 0] += c.cost }
        return costs.max { $0.value < $1.value }.map { ($0.key, $0.value) }
    }

    static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.calendar = Calendar(identifier: .gregorian)
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    // MARK: - Cache

    private struct Cache: Codable {
        var usage: [ProviderUsage]
        var usageFetchedAt: Date?
        var sessions: [SessionRow]
        var sessionsFetchedAt: Date?
        var week: [GraphDay]
        var weekFetchedAt: Date?
    }

    private static var cacheURL: URL { AppPaths.support.appendingPathComponent("cache.json") }

    private func saveCache() {
        let cache = Cache(usage: usage, usageFetchedAt: usageFetchedAt, sessions: sessionsSnapshot,
                          sessionsFetchedAt: sessionsFetchedAt, week: week, weekFetchedAt: weekFetchedAt)
        if let data = try? JSONEncoder().encode(cache) {
            try? data.write(to: Self.cacheURL, options: .atomic)
        }
    }

    private func loadCache() {
        guard let data = try? Data(contentsOf: Self.cacheURL),
              let cache = try? JSONDecoder().decode(Cache.self, from: data) else { return }
        usage = cache.usage
        usageFetchedAt = cache.usageFetchedAt
        sessionsSnapshot = cache.sessions
        sessionsFetchedAt = cache.sessionsFetchedAt
        week = cache.week
        weekFetchedAt = cache.weekFetchedAt
    }
}

enum AppPaths {
    static var support: URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let dir = base.appendingPathComponent("Headroom", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
}

/// Runs a throwing async call and keeps its outcome, so two calls can run in parallel.
func capture<T>(_ body: () async throws -> T) async -> Result<T, Error> {
    do { return .success(try await body()) } catch { return .failure(error) }
}
