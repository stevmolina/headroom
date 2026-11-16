import AppKit
import SwiftUI

// MARK: - Theme

enum Theme {
    /// Amber for "under 20% left". Slightly deeper in light mode for contrast.
    static let amber = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.98, green: 0.70, blue: 0.24, alpha: 1)
            : NSColor(srgbRed: 0.80, green: 0.47, blue: 0.02, alpha: 1)
    })

    /// Red for "under 5% left".
    static let red = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 1.00, green: 0.43, blue: 0.40, alpha: 1)
            : NSColor(srgbRed: 0.84, green: 0.19, blue: 0.17, alpha: 1)
    })

    /// Live-session dot.
    static let live = Color(nsColor: NSColor(name: nil) { appearance in
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            ? NSColor(srgbRed: 0.36, green: 0.84, blue: 0.56, alpha: 1)
            : NSColor(srgbRed: 0.10, green: 0.62, blue: 0.33, alpha: 1)
    })

    static let hairline = Color.primary.opacity(0.08)
    static let track = Color.primary.opacity(0.08)
    static let fill = Color.primary.opacity(0.55)

    static func color(for level: Level) -> Color {
        switch level {
        case .normal: return fill
        case .low: return amber
        case .critical: return red
        }
    }

    static func text(for level: Level) -> Color {
        switch level {
        case .normal: return .primary
        case .low: return amber
        case .critical: return red
        }
    }
}

// MARK: - Monogram

/// A two-letter provider mark in a soft rounded square.
struct MonogramView: View {
    var name: String
    var size: CGFloat = 20

    var body: some View {
        Text(Monogram.letters(name))
            .font(.system(size: size * 0.45, weight: .semibold))
            .tracking(-0.2)
            .foregroundStyle(.primary.opacity(0.8))
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color.primary.opacity(0.06))
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .strokeBorder(Color.primary.opacity(0.09), lineWidth: 0.5)
            )
    }
}

// MARK: - Bar

/// A thin quota bar that eases to its value.
struct QuotaBar: View {
    var remaining: Double
    var level: Level
    var animateIn: Bool

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.track)
                Capsule()
                    .fill(Theme.color(for: level))
                    .frame(width: max(2, geo.size.width * CGFloat(animateIn ? remaining / 100 : 0)))
            }
        }
        .frame(height: 4)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: animateIn)
        .animation(.spring(response: 0.7, dampingFraction: 0.86), value: remaining)
    }
}

// MARK: - Ring

/// The ring used in the menu bar pill: the arc shows how much is left.
struct RingView: View {
    var fraction: Double
    var color: Color
    var lineWidth: CGFloat = 2.2

    var body: some View {
        ZStack {
            Circle().stroke(color.opacity(0.3), lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, fraction)))
                .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
    }
}

// MARK: - Sparkline

/// Seven small day bars, today last and emphasised.
struct WeekBars: View {
    var series: [(date: Date, cost: Double)]
    var animateIn: Bool

    private static let weekday: DateFormatter = {
        let f = DateFormatter()
        f.setLocalizedDateFormatFromTemplate("EEEEE")
        return f
    }()

    var body: some View {
        let maxCost = max(series.map(\.cost).max() ?? 1, 0.01)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(series.enumerated()), id: \.offset) { index, day in
                let isToday = index == series.count - 1
                VStack(spacing: 4) {
                    ZStack(alignment: .bottom) {
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(Theme.track.opacity(0.6))
                        RoundedRectangle(cornerRadius: 2, style: .continuous)
                            .fill(isToday ? Color.primary.opacity(0.75) : Color.primary.opacity(0.28))
                            .frame(height: max(2, 34 * CGFloat(animateIn ? day.cost / maxCost : 0)))
                    }
                    .frame(width: 9, height: 34)
                    Text(Self.weekday.string(from: day.date))
                        .font(.system(size: 8.5, weight: isToday ? .semibold : .regular))
                        .foregroundStyle(isToday ? .secondary : .tertiary)
                }
                .help("\(Fmt.money(day.cost))")
            }
        }
        .animation(.spring(response: 0.8, dampingFraction: 0.85).delay(0.05), value: animateIn)
    }
}

// MARK: - Section header

struct SectionHeader: View {
    var title: String
    var trailing: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title.uppercased())
                .font(.system(size: 10, weight: .semibold))
                .tracking(0.7)
                .foregroundStyle(.secondary)
            Spacer()
            if let trailing {
                Text(trailing)
                    .font(.system(size: 10.5))
                    .monospacedDigit()
                    .foregroundStyle(.tertiary)
            }
        }
    }
}

/// Live green dot with a slow, quiet pulse.
struct LiveDot: View {
    @State private var pulse = false

    var body: some View {
        ZStack {
            Circle().fill(Theme.live.opacity(0.25))
                .frame(width: 10, height: 10)
                .scaleEffect(pulse ? 1 : 0.5)
                .opacity(pulse ? 0 : 1)
            Circle().fill(Theme.live).frame(width: 6, height: 6)
        }
        .frame(width: 10, height: 10)
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Row background that lights up on hover.
struct HoverRow: ViewModifier {
    @State private var hovering = false

    func body(content: Content) -> some View {
        content
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.primary.opacity(hovering ? 0.06 : 0))
                    .padding(.horizontal, -6)
            )
            .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
    }
}

extension View {
    func hoverRow() -> some View { modifier(HoverRow()) }
}
