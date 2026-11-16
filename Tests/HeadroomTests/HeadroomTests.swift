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

    func testLevels() {
        XCTAssertEqual(Level(remaining: 50), .normal)
        XCTAssertEqual(Level(remaining: 19), .low)
        XCTAssertEqual(Level(remaining: 4.9), .critical)
    }
}
