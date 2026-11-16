import SwiftUI

/// The panel's size: narrow, one short page at a time.
enum PanelSize {
    static let width: CGFloat = 380
    static let height: CGFloat = 520
}

// MARK: - Tabs

/// The panel body: one short page at a time. Limits, Today (with what is
/// running now), and Sessions.
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
                        LimitsSection(showsTitle: false, appeared: appeared)
                    case .today:
                        VStack(alignment: .leading, spacing: 22) {
                            TodaySection(showsTitle: false, appeared: appeared)
                            NowSection(onSelect: onSelect)
                        }
                    case .sessions:
                        SessionsSection(showsTitle: false, onSelect: onSelect)
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
