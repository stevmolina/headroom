import SwiftUI

/// Panel arrangements. `stack` is the original single column.
enum PanelLayout: String, CaseIterable {
    case stack, tabs, wide, tiles

    var title: String {
        switch self {
        case .stack: return "Single column"
        case .tabs: return "Tabs"
        case .wide: return "Two columns"
        case .tiles: return "Tiles"
        }
    }

    var size: CGSize {
        switch self {
        case .stack: return CGSize(width: 360, height: 620)
        case .tabs: return CGSize(width: 380, height: 500)
        case .wide: return CGSize(width: 720, height: 520)
        case .tiles: return CGSize(width: 680, height: 500)
        }
    }
}

// MARK: - Tabs

/// One short page at a time: Limits, Today (with what is running), Sessions.
struct TabsLayout: View {
    enum Tab: String, CaseIterable { case limits = "Limits", today = "Today", sessions = "Sessions" }

    @Environment(UsageStore.self) private var store
    var appeared: Bool
    var onSelect: (SessionRow) -> Void
    @State private var tab: Tab = .limits

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $tab.animation(.smooth(duration: 0.25))) {
                ForEach(Tab.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView(.vertical, showsIndicators: false) {
                Group {
                    switch tab {
                    case .limits:
                        LimitsSection(appeared: appeared)
                    case .today:
                        VStack(alignment: .leading, spacing: 22) {
                            TodaySection(appeared: appeared)
                            NowSection(onSelect: onSelect)
                        }
                    case .sessions:
                        SessionsSection(onSelect: onSelect)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.top, 4)
                .padding(.bottom, 16)
                .transition(.opacity)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .headroomCommand)) { note in
            let c = note.object as? String ?? ""
            if c.hasPrefix("tab:"), let t = Tab.allCases.first(where: { $0.rawValue.lowercased() == c.dropFirst(4) }) {
                withAnimation(.smooth(duration: 0.25)) { tab = t }
            }
        }
    }
}

// MARK: - Two columns

/// Limits on the left, activity on the right, both visible at once.
struct WideLayout: View {
    var appeared: Bool
    var onSelect: (SessionRow) -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ScrollView(.vertical, showsIndicators: false) {
                LimitsSection(appeared: appeared)
                    .padding(16)
            }
            .frame(width: 360)
            Rectangle().fill(Theme.hairline).frame(width: 1)
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    TodaySection(appeared: appeared)
                    NowSection(onSelect: onSelect)
                    SessionsSection(onSelect: onSelect)
                }
                .padding(16)
            }
            .frame(maxWidth: .infinity)
        }
    }
}

// MARK: - Tiles

/// One card per provider with a dial per limit, then today in one strip.
struct TilesLayout: View {
    @Environment(UsageStore.self) private var store
    var appeared: Bool
    var onSelect: (SessionRow) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 10, alignment: .top), count: 3)

    var body: some View {
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                LazyVGrid(columns: columns, alignment: .leading, spacing: 10) {
                    ForEach(store.limitGroups) { group in
                        ProviderTile(group: group, now: store.now, appeared: appeared)
                    }
                }
                TodayStrip(appeared: appeared)
                NowSection(onSelect: onSelect)
                SessionsSection(onSelect: onSelect)
            }
            .padding(16)
        }
    }
}

private struct ProviderTile: View {
    var group: LimitGroup
    var now: Date
    var appeared: Bool

    var body: some View {
        let warning = group.rows.compactMap { r in r.runsOutIn.map { (r, $0) } }
            .filter { $0.1 < 24 * 3600 || Level(remaining: $0.0.remaining) != .normal }
            .min { $0.1 < $1.1 }
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 7) {
                MonogramView(name: group.provider, size: 18)
                VStack(alignment: .leading, spacing: 0) {
                    Text(group.provider).font(.system(size: 12, weight: .medium))
                    if let sub = group.group ?? group.plan {
                        Text(sub).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .top, spacing: 14) {
                ForEach(group.rows) { row in
                    MetricDial(row: row, now: now, appeared: appeared)
                }
                Spacer(minLength: 0)
            }
            if let (row, out) = warning {
                Text("\(row.metric): out in \(Fmt.about(out).replacingOccurrences(of: "about ", with: "~"))")
                    .font(.system(size: 10))
                    .foregroundStyle(Level(remaining: row.remaining) == .normal ? Theme.amber : Theme.text(for: Level(remaining: row.remaining)))
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
    }
}

/// A small ring with the % left inside, the limit's name and its reset below.
private struct MetricDial: View {
    var row: LimitRow
    var now: Date
    var appeared: Bool

    var body: some View {
        let level = Level(remaining: row.remaining)
        VStack(spacing: 4) {
            ZStack {
                RingView(fraction: appeared ? row.remaining / 100 : 0,
                         color: level == .normal ? Color.primary.opacity(0.7) : Theme.color(for: level),
                         lineWidth: 3.5)
                    .animation(.spring(response: 0.8, dampingFraction: 0.85), value: appeared)
                Text(Fmt.percent(row.remaining).replacingOccurrences(of: "%", with: ""))
                    .font(.system(size: 11.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text(for: level))
            }
            .frame(width: 40, height: 40)
            Text(row.metric).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            Text(row.resetsAt.map { Fmt.reset($0, now: now) } ?? " ")
                .font(.system(size: 9.5)).monospacedDigit().foregroundStyle(.tertiary).lineLimit(1)
        }
        .frame(minWidth: 46)
    }
}

/// Today's cost, tokens, week bars and top model on one line.
private struct TodayStrip: View {
    @Environment(UsageStore.self) private var store
    var appeared: Bool

    var body: some View {
        let today = store.today
        HStack(alignment: .center, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("TODAY").font(.system(size: 10, weight: .semibold)).tracking(0.7).foregroundStyle(.secondary)
                Text(Fmt.money(today?.totals.cost ?? 0))
                    .font(.system(size: 24, weight: .semibold)).monospacedDigit()
                    .contentTransition(.numericText(value: today?.totals.cost ?? 0))
            }
            VStack(alignment: .leading, spacing: 3) {
                Text(verbatim: "\(Fmt.tokens(today?.totals.tokens ?? 0)) tokens")
                Text(verbatim: "\(Fmt.count(today?.totals.messages ?? 0)) messages")
                if let top = store.topModelToday {
                    Text(verbatim: "Top: \(Fmt.model(top.model))")
                }
            }
            .font(.system(size: 11))
            .monospacedDigit()
            .foregroundStyle(.secondary)
            Spacer()
            WeekBars(series: store.weekSeries, animateIn: appeared)
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.primary.opacity(0.045)))
    }
}
