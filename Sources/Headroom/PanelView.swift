import ServiceManagement
import SwiftUI

struct PanelView: View {
    @Environment(UsageStore.self) private var store
    /// The open session, by id, so the detail always shows the latest reading.
    @State private var selectedID: String?

    private var selected: SessionRow? {
        selectedID.flatMap { id in store.sessions.first { $0.id == id } }
    }
    @State private var appeared = false
    @State private var tab: TabsLayout.Tab = .limits

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                if let selected {
                    SessionDetailView(session: selected, now: store.now) {
                        withAnimation(.smooth(duration: 0.32)) { self.selectedID = nil }
                    }
                    .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                            removal: .move(edge: .trailing).combined(with: .opacity)))
                } else {
                    overview
                        .transition(.asymmetric(insertion: .move(edge: .leading).combined(with: .opacity),
                                                removal: .move(edge: .leading).combined(with: .opacity)))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .clipped()
        }
        .frame(width: PanelSize.width)
        .frame(maxHeight: .infinity)
        .onAppear { playEntrance() }
        .onReceive(NotificationCenter.default.publisher(for: .headroomPanelOpened)) { _ in playEntrance() }
        .onReceive(NotificationCenter.default.publisher(for: .headroomCommand)) { note in
            let command = note.object as? String ?? ""
            if command == "back" { withAnimation(.smooth(duration: 0.32)) { selectedID = nil } }
            if command.hasPrefix("tab:"),
               let t = TabsLayout.Tab.allCases.first(where: { $0.rawValue.lowercased() == command.dropFirst(4) }) {
                withAnimation(.smooth(duration: 0.25)) {
                    selectedID = nil
                    tab = t
                }
            }
            if command.hasPrefix("session:"), let i = Int(command.dropFirst(8)), store.sessions.indices.contains(i) {
                open(store.sessions[i])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .headroomPanelClosed)) { _ in
            selectedID = nil
            appeared = false
        }
    }

    // MARK: Overview

    private var overview: some View {
        VStack(spacing: 0) {
            header
            Rectangle().fill(Theme.hairline).frame(height: 1)
            TabsLayout(appeared: appeared, onSelect: open, tab: $tab)
            if let error = store.lastError {
                Rectangle().fill(Theme.hairline).frame(height: 1)
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle")
                    Text(error).lineLimit(2)
                    Spacer(minLength: 0)
                }
                .font(.system(size: 10.5))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 16)
                .padding(.vertical, 8)
            }
        }
    }

    /// Bars grow from zero each time the panel opens.
    private func playEntrance() {
        appeared = false
        withAnimation(.spring(response: 0.7, dampingFraction: 0.86).delay(0.08)) { appeared = true }
    }

    private func open(_ session: SessionRow) {
        withAnimation(.smooth(duration: 0.32)) { selectedID = session.id }
    }

    private var header: some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 1) {
                Text("Headroom")
                    .font(.system(size: 13, weight: .semibold))
                Text(updatedLabel)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .contentTransition(.numericText())
            }
            Spacer()
            Button {
                store.refreshAll()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .rotationEffect(.degrees(store.isRefreshingUsage || store.isRefreshingSessions ? 360 : 0))
                    .animation(store.isRefreshingUsage || store.isRefreshingSessions
                               ? .linear(duration: 0.9).repeatForever(autoreverses: false) : .default,
                               value: store.isRefreshingUsage || store.isRefreshingSessions)
            }
            .buttonStyle(IconButtonStyle())
            .help("Refresh now")
            SettingsMenu()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 11)
    }

    private var updatedLabel: String {
        if store.usageFetchedAt == nil && store.isRefreshingUsage { return "Reading tokscale…" }
        let age = Fmt.age(store.usageFetchedAt, now: store.now)
        return "Updated \(age)" + (store.isRefreshingUsage ? " · refreshing" : "")
    }
}

// MARK: - Limits

struct LimitsSection: View {
    @Environment(UsageStore.self) private var store
    /// Off inside a tab whose name already says it.
    var showsTitle = true
    var appeared: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: showsTitle ? "Limits" : "", trailing: "% left · resets")
            if store.limitGroups.isEmpty {
                Placeholder(text: store.isRefreshingUsage ? "Reading quotas…" : "No quota data yet")
            }
            ForEach(store.limitGroups) { group in
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        MonogramView(name: group.provider)
                        Text(group.provider)
                            .font(.system(size: 12.5, weight: .medium))
                        if let sub = group.group {
                            Text(sub)
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 4)
                        if let plan = group.plan {
                            Text(plan)
                                .font(.system(size: 10.5))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    ForEach(group.rows) { row in
                        LimitRowView(row: row, now: store.now, appeared: appeared)
                    }
                }
            }
        }
    }
}

private struct LimitRowView: View {
    var row: LimitRow
    var now: Date
    var appeared: Bool

    var body: some View {
        let level = Level(remaining: row.remaining)
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(row.metric)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .frame(width: 52, alignment: .leading)
                QuotaBar(remaining: row.remaining, level: level, animateIn: appeared)
                Text(Fmt.percent(row.remaining))
                    .font(.system(size: 11.5, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(Theme.text(for: level))
                    .contentTransition(.numericText(value: row.remaining))
                    .frame(width: 36, alignment: .trailing)
                Text(row.resetsAt.map { Fmt.reset($0, now: now) } ?? "")
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .frame(width: 62, alignment: .trailing)
                    .help(row.resetsAt.map { "Resets \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "")
            }
            if let out = row.runsOutIn, out < 24 * 3600 || level != .normal {
                Text("Runs out in \(Fmt.about(out)), before the reset")
                    .font(.system(size: 10.5))
                    .foregroundStyle(level == .normal ? Theme.amber : Theme.text(for: level))
                    .padding(.leading, 62)
            }
        }
        .padding(.leading, 28)
    }
}

// MARK: - Now

struct NowSection: View {
    @Environment(UsageStore.self) private var store
    var onSelect: (SessionRow) -> Void

    var body: some View {
        let live = store.liveSessions
        VStack(alignment: .leading, spacing: 8) {
            SectionHeader(title: "Now", trailing: live.isEmpty ? nil : "\(live.count) running")
            if live.isEmpty {
                Placeholder(text: "No agent is working right now")
            }
            ForEach(live) { s in
                Button { onSelect(s) } label: {
                    HStack(spacing: 8) {
                        LiveDot()
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Redact.project(s.projectName))
                                .font(.system(size: 12.5, weight: .medium))
                                .lineLimit(1)
                            Text("\(Fmt.client(s.client)) · \(Fmt.model(s.primaryModel))")
                                .font(.system(size: 10.5))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        VStack(alignment: .trailing, spacing: 1) {
                            Text(Fmt.money(s.cost))
                                .font(.system(size: 12, weight: .medium))
                                .monospacedDigit()
                                .contentTransition(.numericText(value: s.cost))
                            Text(Fmt.duration(store.now.timeIntervalSince(s.firstActive)))
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.vertical, 4)
                    .hoverRow()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Today

struct TodaySection: View {
    @Environment(UsageStore.self) private var store
    /// Off inside a tab whose name already says it.
    var showsTitle = true
    var appeared: Bool

    var body: some View {
        let today = store.today
        VStack(alignment: .leading, spacing: 10) {
            SectionHeader(title: showsTitle ? "Today" : "", trailing: store.weekFetchedAt.map { "as of " + Fmt.clock($0) })
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(Fmt.money(today?.totals.cost ?? 0))
                        .font(.system(size: 26, weight: .semibold))
                        .monospacedDigit()
                        .contentTransition(.numericText(value: today?.totals.cost ?? 0))
                    Text(verbatim: "\(Fmt.tokens(today?.totals.tokens ?? 0)) tokens · \(Fmt.count(today?.totals.messages ?? 0)) messages")
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
                WeekBars(series: store.weekSeries, animateIn: appeared)
            }
            if let top = store.topModelToday {
                HStack(spacing: 6) {
                    Text("Top model")
                        .foregroundStyle(.secondary)
                    Text(Fmt.model(top.model))
                        .fontWeight(.medium)
                    Spacer()
                    Text(Fmt.money(top.cost))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .font(.system(size: 11.5))
                .padding(.vertical, 7)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04))
                )
            }
        }
    }
}

// MARK: - Sessions

struct SessionsSection: View {
    @Environment(UsageStore.self) private var store
    /// Off inside a tab whose name already says it.
    var showsTitle = true
    var onSelect: (SessionRow) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            SectionHeader(title: showsTitle ? "Sessions" : "", trailing: store.sessions.isEmpty ? nil : "\(store.sessions.count) today")
                .padding(.bottom, 4)
            if store.sessions.isEmpty {
                Placeholder(text: store.isRefreshingSessions ? "Reading sessions…" : "No sessions today")
            }
            ForEach(store.sessions) { s in
                Button { onSelect(s) } label: {
                    HStack(spacing: 8) {
                        MonogramView(name: s.client, size: 18)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(Redact.project(s.projectName))
                                .font(.system(size: 12))
                                .lineLimit(1)
                            Text("\(Fmt.model(s.primaryModel)) · \(Fmt.clock(s.firstActive))")
                                .font(.system(size: 10.5))
                                .monospacedDigit()
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                        Spacer(minLength: 6)
                        Text(Fmt.duration(s.duration))
                            .font(.system(size: 11))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                        Text(Fmt.money(s.cost))
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .frame(minWidth: 52, alignment: .trailing)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 9, weight: .semibold))
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.vertical, 5)
                    .hoverRow()
                }
                .buttonStyle(.plain)
            }
        }
    }
}

// MARK: - Session detail

struct SessionDetailView: View {
    var session: SessionRow
    var now: Date
    var onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold))
                        Text("Back")
                    }
                }
                .buttonStyle(IconButtonStyle())
                .keyboardShortcut(.cancelAction)
                Spacer()
                if now.timeIntervalSince(session.lastActive) < 300 {
                    HStack(spacing: 5) { LiveDot(); Text("Running").foregroundStyle(.secondary) }
                        .font(.system(size: 11))
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            Rectangle().fill(Theme.hairline).frame(height: 1)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    HStack(spacing: 10) {
                        MonogramView(name: session.client, size: 30)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(Redact.project(session.projectName))
                                .font(.system(size: 15, weight: .semibold))
                                .lineLimit(1)
                            Text(Fmt.client(session.client))
                                .font(.system(size: 11.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let title = session.title, !Redact.enabled {
                        Text(title).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(3)
                    }

                    VStack(alignment: .leading, spacing: 2) {
                        Text(Fmt.money(session.cost))
                            .font(.system(size: 30, weight: .semibold))
                            .monospacedDigit()
                        Text(verbatim: "\(Fmt.tokens(session.totalTokens)) tokens across \(Fmt.count(session.messageCount)) messages")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    TokenSplit(session: session)

                    VStack(spacing: 0) {
                        DetailLine(label: "Model", value: session.models.map(Fmt.model).joined(separator: ", "))
                        DetailLine(label: "Duration", value: Fmt.duration(session.duration))
                        DetailLine(label: "Started", value: Fmt.clock(session.firstActive))
                        DetailLine(label: "Last activity", value: Fmt.age(session.lastActive, now: now))
                        DetailLine(label: "Turns", value: "\(session.turnCount)")
                        if session.subagentCount > 0 {
                            DetailLine(label: "Subagents", value: "\(session.subagentCount)")
                        }
                        DetailLine(label: "Project", value: Redact.project(session.projectName), last: true)
                    }
                }
                .padding(16)
            }
        }
    }
}

/// Input, output and cache tokens as one stacked bar with a legend.
private struct TokenSplit: View {
    var session: SessionRow
    @State private var shown = false

    var body: some View {
        let parts: [(String, Int, Double)] = [
            ("Input", session.input, 0.85),
            ("Output", session.output, 0.6),
            ("Cache read", session.cacheRead, 0.32),
            ("Cache write", session.cacheWrite, 0.18),
        ]
        let total = max(1, parts.map(\.1).reduce(0, +))
        VStack(alignment: .leading, spacing: 10) {
            GeometryReader { geo in
                HStack(spacing: 2) {
                    ForEach(parts, id: \.0) { part in
                        if part.1 > 0 {
                            RoundedRectangle(cornerRadius: 2, style: .continuous)
                                .fill(Color.primary.opacity(part.2))
                                .frame(width: max(3, (geo.size.width - 6) * CGFloat(part.1) / CGFloat(total)))
                        }
                    }
                }
                .frame(width: shown ? geo.size.width : 0, alignment: .leading)
                .clipped()
            }
            .frame(height: 6)
            Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                GridRow {
                    legend(parts[0]); legend(parts[1])
                }
                GridRow {
                    legend(parts[2]); legend(parts[3])
                }
            }
        }
        .onAppear { withAnimation(.spring(response: 0.7, dampingFraction: 0.9).delay(0.1)) { shown = true } }
    }

    private func legend(_ part: (String, Int, Double)) -> some View {
        HStack(spacing: 6) {
            RoundedRectangle(cornerRadius: 1.5).fill(Color.primary.opacity(part.2)).frame(width: 8, height: 8)
            Text(part.0).foregroundStyle(.secondary)
            Text(Fmt.tokens(part.1)).monospacedDigit().fontWeight(.medium)
        }
        .font(.system(size: 11))
    }
}

private struct DetailLine: View {
    var label: String
    var value: String
    var last = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(label).foregroundStyle(.secondary)
                Spacer()
                Text(value).monospacedDigit().multilineTextAlignment(.trailing).lineLimit(2)
            }
            .font(.system(size: 12))
            .padding(.vertical, 8)
            if !last { Rectangle().fill(Theme.hairline).frame(height: 1) }
        }
    }
}

// MARK: - Small pieces

struct Placeholder: View {
    var text: String
    var body: some View {
        Text(text)
            .font(.system(size: 11.5))
            .foregroundStyle(.tertiary)
            .padding(.vertical, 2)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        IconButtonBody(configuration: configuration)
    }

    private struct IconButtonBody: View {
        var configuration: Configuration
        @State private var hovering = false

        var body: some View {
            configuration.label
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 6)
                .frame(minWidth: 26, minHeight: 24)
                .background(
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(Color.primary.opacity(configuration.isPressed ? 0.12 : hovering ? 0.07 : 0))
                )
                .contentShape(Rectangle())
                .onHover { hovering = $0 }
        }
    }
}

private struct SettingsMenu: View {
    @Environment(UsageStore.self) private var store
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Menu {
            Section("Count in the menu bar") {
                ForEach(store.providerNames, id: \.self) { name in
                    Toggle(name, isOn: Binding(
                        get: { !store.hiddenProviders.contains(name) },
                        set: { on in
                            if on { store.hiddenProviders.remove(name) } else { store.hiddenProviders.insert(name) }
                        }
                    ))
                }
            }
            Toggle("Launch at login", isOn: Binding(
                get: { launchAtLogin },
                set: { on in
                    do {
                        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch {}
                    launchAtLogin = SMAppService.mainApp.status == .enabled
                }
            ))
            Divider()
            Text(store.tokscalePath.map { "tokscale: \($0)" } ?? "tokscale not found")
            Divider()
            Button("Quit Headroom") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        } label: {
            Image(systemName: "ellipsis")
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .buttonStyle(IconButtonStyle())
    }
}

// MARK: - Project names

extension SessionRow {
    /// Short project name: the GitHub repo when the folder is a git repo,
    /// else a readable name for the folder. See ProjectNamer.
    var projectName: String { ProjectNamer.name(workspace: workspace, path: workspacePath) }
}

/// Hides project names for public screenshots (`HEADROOM_REDACT=1`).
enum Redact {
    static let enabled = ProcessInfo.processInfo.environment["HEADROOM_REDACT"] == "1"
    private static var names: [String: String] = [:]

    static func project(_ name: String) -> String {
        guard enabled else { return name }
        if let n = names[name] { return n }
        let letter = String(UnicodeScalar(UInt8(65 + names.count % 26)))
        let label = "Project \(letter)"
        names[name] = label
        return label
    }
}
