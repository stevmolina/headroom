import Foundation

// MARK: - `tokscale usage --json`

/// One provider card from `tokscale usage --json`. Antigravity returns one card
/// per quota group, told apart by `account.label`.
struct ProviderUsage: Codable, Hashable {
    struct Account: Codable, Hashable {
        var id: String?
        var label: String?
    }

    struct Metric: Codable, Hashable {
        var label: String
        var usedPercent: Double
        var remainingPercent: Double
        var remainingLabel: String?
        var resetsAt: Date?

        enum CodingKeys: String, CodingKey {
            case label
            case usedPercent = "used_percent"
            case remainingPercent = "remaining_percent"
            case remainingLabel = "remaining_label"
            case resetsAt = "resets_at"
        }
    }

    var provider: String
    var plan: String?
    var account: Account?
    var metrics: [Metric]
}

// MARK: - `tokscale sessions --json`

struct SessionsReport: Codable {
    var sessions: [SessionRow]
    var totalCost: Double
}

struct SessionRow: Codable, Hashable, Identifiable {
    var client: String
    var sessionId: String
    var title: String?
    var workspace: String?
    var workspacePath: String?
    var models: [String]
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var reasoning: Int
    var cost: Double
    var messageCount: Int
    var turnCount: Int
    var subagentCount: Int
    var firstActiveMs: Int64
    var lastActiveMs: Int64

    var id: String { client + ":" + sessionId }
    var firstActive: Date { Date(timeIntervalSince1970: Double(firstActiveMs) / 1000) }
    var lastActive: Date { Date(timeIntervalSince1970: Double(lastActiveMs) / 1000) }
    var duration: TimeInterval { max(0, Double(lastActiveMs - firstActiveMs) / 1000) }
    var totalTokens: Int { input + output + cacheRead + cacheWrite + reasoning }
    var primaryModel: String { models.first ?? "unknown" }
}

// MARK: - `tokscale graph --week`

struct GraphReport: Codable {
    var contributions: [GraphDay]
}

struct GraphDay: Codable, Hashable {
    struct Totals: Codable, Hashable {
        var tokens: Int
        var cost: Double
        var messages: Int
    }

    struct ClientModel: Codable, Hashable {
        var client: String
        var modelId: String
        var cost: Double
        var messages: Int
    }

    var date: String
    var totals: Totals
    var clients: [ClientModel]
}
