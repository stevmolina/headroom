import XCTest
@testable import Headroom

final class HeadroomTests: XCTestCase {
    func testParsesTokscaleDates() {
        let a = parseISODate("2026-11-16T21:00:00.678508+00:00")
        let b = parseISODate("2026-11-21T22:51:03Z")
        XCTAssertNotNil(a)
        XCTAssertNotNil(b)
        XCTAssertEqual(a!.timeIntervalSince1970.truncatingRemainder(dividingBy: 1), 0.678508, accuracy: 0.0001)
    }

    func testDecodesUsageJSON() throws {
        let json = """
        [{"provider":"Antigravity","account":{"id":"g","label":"Gemini Models","is_active":true},
          "plan":null,"email":null,"metrics":[{"label":"weekly","used_percent":52.1,
          "remaining_percent":47.9,"remaining_label":null,"resets_at":"2026-11-21T22:51:03Z"}]}]
        """
        let usage = try Tokscale.decoder.decode([ProviderUsage].self, from: Data(json.utf8))
        XCTAssertEqual(usage.first?.account?.label, "Gemini Models")
        XCTAssertEqual(usage.first?.metrics.first?.remainingPercent, 47.9)
    }

    func testModelNames() {
        XCTAssertEqual(Fmt.model("claude-opus-5-5"), "Opus 5.5")
        XCTAssertEqual(Fmt.model("claude-sonnet-5-5"), "Sonnet 5.5")
        XCTAssertEqual(Fmt.model("gpt-6.1-sol"), "GPT-6.1 Sol")
    }

    func testRunsOutUsesWindowPaceWithoutHistory() {
        let now = Date()
        // Weekly window, 2 days elapsed, 76% used: about 38%/day, 24% left
        // lasts ~15h, and the reset is 5 days out, so it runs out first.
        let reset = now.addingTimeInterval(5 * 86400)
        let out = Burn.runsOutIn(metricId: "x", label: "Weekly", used: 76, resetsAt: reset,
                                 history: QuotaHistory(), now: now)
        XCTAssertNotNil(out)
        XCTAssertEqual(out! / 3600, 15.2, accuracy: 0.5)
    }

    func testNoForecastWhenPaceIsSafe() {
        let now = Date()
        let reset = now.addingTimeInterval(1 * 86400)
        let out = Burn.runsOutIn(metricId: "x", label: "Weekly", used: 20, resetsAt: reset,
                                 history: QuotaHistory(), now: now)
        XCTAssertNil(out)
    }

    func testRecentTrendBeatsWindowAverage() {
        let now = Date()
        let reset = now.addingTimeInterval(4 * 3600)
        var h = QuotaHistory()
        h.record(id: "x", sample: .init(at: now.addingTimeInterval(-1800), used: 40, resetsAt: reset))
        // 40% → 60% in 30 min: 40 points left at 40%/h is ~1h, well before the 4h reset.
        let out = Burn.runsOutIn(metricId: "x", label: "5h", used: 60, resetsAt: reset, history: h, now: now)
        XCTAssertEqual(out! / 3600, 1.0, accuracy: 0.05)
    }

    func testPercentMatchesTokscaleRounding() {
        XCTAssertEqual(Fmt.percent(47.85885), "48%")
        XCTAssertEqual(Fmt.percent(1.3384), "1%")
        XCTAssertEqual(Fmt.percent(0.4), "0.4%")
        XCTAssertEqual(Fmt.percent(0), "0%")
    }

    func testHistoryKeepsReadingsFiveMinutesApart() {
        var h = QuotaHistory()
        let start = Date()
        // 60 polls, one a minute: about 12 readings should survive, not one.
        for i in 0..<60 {
            h.record(id: "x", sample: .init(at: start.addingTimeInterval(Double(i) * 60), used: Double(i), resetsAt: nil))
        }
        let count = h.samples["x"]?.count ?? 0
        XCTAssertGreaterThanOrEqual(count, 10)
        XCTAssertEqual(h.samples["x"]?.last?.used, 59)
    }

    func testIdleTrendGivesNoForecast() {
        let now = Date()
        let reset = now.addingTimeInterval(4 * 3600)
        var h = QuotaHistory()
        h.record(id: "x", sample: .init(at: now.addingTimeInterval(-1800), used: 60, resetsAt: reset))
        XCTAssertNil(Burn.runsOutIn(metricId: "x", label: "5h", used: 60, resetsAt: reset, history: h, now: now))
    }

    func testRunTimesOutInsteadOfHanging() async {
        let sleep = Tokscale(executable: URL(fileURLWithPath: "/bin/sleep"))
        let started = Date()
        do {
            _ = try await sleep.run(["30"], timeout: 1)
            XCTFail("expected a timeout")
        } catch {
            XCTAssertLessThan(Date().timeIntervalSince(started), 8)
        }
    }

    func testRunReturnsOutputAndReportsMissingBinary() async throws {
        let echo = Tokscale(executable: URL(fileURLWithPath: "/bin/echo"))
        let data = try await echo.run(["hello"], timeout: 5)
        XCTAssertEqual(String(decoding: data, as: UTF8.self), "hello\n")
        let missing = Tokscale(executable: URL(fileURLWithPath: "/nonexistent/tokscale"))
        do { _ = try await missing.run([], timeout: 5); XCTFail("expected an error") } catch {}
    }

    func testSessionRowToleratesMissingFields() throws {
        let json = #"{"sessions":[{"client":"codex","sessionId":"s1","models":null,"cost":1.5}],"totalCost":1.5}"#
        let report = try Tokscale.decoder.decode(SessionsReport.self, from: Data(json.utf8))
        XCTAssertEqual(report.sessions.first?.models, [])
        XCTAssertEqual(report.sessions.first?.cost, 1.5)
    }

    func testProjectNamesFromSlugs() {
        let home = "/Users/me"
        XCTAssertEqual(ProjectNamer.fromSlug("-Users-me--t3-worktrees-rooms-t3-bced9cd1", home: home), "rooms")
        XCTAssertEqual(ProjectNamer.fromSlug("-Users-me--t3-worktrees-steven-agents-t3-0a1b2c3d", home: home), "steven-agents")
        XCTAssertEqual(ProjectNamer.fromSlug("-Users-me-Dev", home: home), "~/dev")
        XCTAssertEqual(ProjectNamer.fromSlug("-Users-me", home: home), "~")
        XCTAssertEqual(ProjectNamer.fromSlug("-Users-me-dev-api--claude-worktrees-fix", home: home), "api")
        XCTAssertEqual(ProjectNamer.resolve(workspace: nil, path: "/Users/me/OpenBot/Agents/agent-1", home: home), "OpenBot agent")
        XCTAssertEqual(ProjectNamer.resolve(workspace: nil, path: nil, home: home), "No project")
    }

    func testRepoNameFromRemote() {
        XCTAssertEqual(ProjectNamer.repoName(fromRemote: "git@github.com:me/headroom.git"), "headroom")
        XCTAssertEqual(ProjectNamer.repoName(fromRemote: "https://github.com/me/tokscale"), "tokscale")
    }

    func testRealWorktreeResolvesToMainRepo() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("hr-\(UUID().uuidString)").path
        let repo = root + "/main-folder", wt = root + "/wt/t3-abc"
        try fm.createDirectory(atPath: repo + "/.git/worktrees/t3-abc", withIntermediateDirectories: true)
        try fm.createDirectory(atPath: wt + "/src", withIntermediateDirectories: true)
        try "[remote \"origin\"]\n\turl = git@github.com:me/real-repo.git\n".write(toFile: repo + "/.git/config", atomically: true, encoding: .utf8)
        try "gitdir: \(repo)/.git/worktrees/t3-abc\n".write(toFile: wt + "/.git", atomically: true, encoding: .utf8)
        XCTAssertEqual(ProjectNamer.gitRepoName(startingAt: wt + "/src", home: root), "real-repo")
        try? fm.removeItem(atPath: root)
    }

    func testLevels() {
        XCTAssertEqual(Level(remaining: 50), .normal)
        XCTAssertEqual(Level(remaining: 19), .low)
        XCTAssertEqual(Level(remaining: 4.9), .critical)
    }
}
