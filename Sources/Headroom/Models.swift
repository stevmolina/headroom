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

    enum CodingKeys: String, CodingKey {
        case client, sessionId, title, workspace, workspacePath, models, input, output, cacheRead, cacheWrite,
             reasoning, cost, messageCount, turnCount, subagentCount, firstActiveMs, lastActiveMs
    }

    /// Lenient: a missing or null field becomes empty or zero instead of
    /// failing the whole sessions list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        func int(_ k: CodingKeys) -> Int { (try? c.decodeIfPresent(Int.self, forKey: k)) ?? 0 }
        func int64(_ k: CodingKeys) -> Int64 { (try? c.decodeIfPresent(Int64.self, forKey: k)) ?? 0 }
        client = (try? c.decodeIfPresent(String.self, forKey: .client)) ?? "unknown"
        sessionId = (try? c.decodeIfPresent(String.self, forKey: .sessionId)) ?? UUID().uuidString
        title = try? c.decodeIfPresent(String.self, forKey: .title)
        workspace = try? c.decodeIfPresent(String.self, forKey: .workspace)
        workspacePath = try? c.decodeIfPresent(String.self, forKey: .workspacePath)
        models = (try? c.decodeIfPresent([String].self, forKey: .models)) ?? []
        input = int(.input); output = int(.output); cacheRead = int(.cacheRead)
        cacheWrite = int(.cacheWrite); reasoning = int(.reasoning)
        cost = (try? c.decodeIfPresent(Double.self, forKey: .cost)) ?? 0
        messageCount = int(.messageCount); turnCount = int(.turnCount); subagentCount = int(.subagentCount)
        firstActiveMs = int64(.firstActiveMs); lastActiveMs = int64(.lastActiveMs)
    }

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
