import Foundation

/// Runs the tokscale CLI and decodes its JSON. Every call runs on a background
/// thread; nothing here touches the main actor.
struct Tokscale: Sendable {
    enum Failure: LocalizedError {
        case notFound
        case timedOut(String)
        case exit(Int32, String)
        case decode(String, String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "tokscale not found. Set its path in Settings."
            case .timedOut(let cmd):
                return "tokscale \(cmd) timed out"
            case .exit(let code, let err):
                return "tokscale exited \(code): \(err.prefix(160))"
            case .decode(let cmd, let detail):
                return "Could not read tokscale \(cmd): \(detail)"
            }
        }
    }

    let executable: URL

    /// Finds the binary: an explicit setting first, then the usual install places.
    static func locate(override: String?) -> Tokscale? {
        let fm = FileManager.default
        let home = fm.homeDirectoryForCurrentUser.path
        var candidates: [String] = []
        if let override, !override.isEmpty { candidates.append((override as NSString).expandingTildeInPath) }
        if let env = ProcessInfo.processInfo.environment["HEADROOM_TOKSCALE"] { candidates.append(env) }
        candidates += [
            "\(home)/.local/bin/tokscale",
            "/opt/homebrew/bin/tokscale",
            "/usr/local/bin/tokscale",
            "\(home)/.cargo/bin/tokscale",
        ]
        for path in candidates where fm.isExecutableFile(atPath: path) {
            return Tokscale(executable: URL(fileURLWithPath: path))
        }
        return nil
    }

    func usage() async throws -> [ProviderUsage] {
        try await decode([ProviderUsage].self, args: ["usage", "--json"], timeout: 45)
    }

    func sessionsToday() async throws -> SessionsReport {
        try await decode(SessionsReport.self, args: ["sessions", "--json", "--today", "--no-spinner"], timeout: 120)
    }

    func week() async throws -> GraphReport {
        try await decode(GraphReport.self, args: ["graph", "--week", "--no-spinner"], timeout: 120)
    }

    // MARK: - Process plumbing

    private func decode<T: Decodable>(_ type: T.Type, args: [String], timeout: TimeInterval) async throws -> T {
        let data = try await run(args, timeout: timeout)
        do {
            return try Self.decoder.decode(T.self, from: data)
        } catch {
            throw Failure.decode(args.first ?? "", String(describing: error).prefix(200).description)
        }
    }

    func run(_ args: [String], timeout: TimeInterval) async throws -> Data {
        let executable = self.executable
        return try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .utility).async {
                let process = Process()
                process.executableURL = executable
                process.arguments = args
                var env = ProcessInfo.processInfo.environment
                env["NO_COLOR"] = "1"
                process.environment = env
                let out = Pipe()
                let err = Pipe()
                process.standardOutput = out
                process.standardError = err

                // Drain both pipes while the process runs so a large report
                // never blocks on a full pipe buffer.
                var outData = Data()
                var errData = Data()
                let group = DispatchGroup()
                group.enter()
                DispatchQueue.global().async {
                    outData = out.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }
                group.enter()
                DispatchQueue.global().async {
                    errData = err.fileHandleForReading.readDataToEndOfFile()
                    group.leave()
                }

                do {
                    try process.run()
                } catch {
                    continuation.resume(throwing: error)
                    return
                }

                let timer = DispatchWorkItem { if process.isRunning { process.terminate() } }
                DispatchQueue.global().asyncAfter(deadline: .now() + timeout, execute: timer)
                process.waitUntilExit()
                timer.cancel()
                group.wait()

                if process.terminationReason == .uncaughtSignal {
                    continuation.resume(throwing: Failure.timedOut(args.first ?? ""))
                } else if process.terminationStatus != 0 {
                    let message = String(decoding: errData, as: UTF8.self)
                    continuation.resume(throwing: Failure.exit(process.terminationStatus, message))
                } else {
                    continuation.resume(returning: outData)
                }
            }
        }
    }

    static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let raw = try container.decode(String.self)
            guard let date = parseISODate(raw) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Bad date \(raw)")
            }
            return date
        }
        return d
    }()
}

/// Parses tokscale's timestamps, which mix `Z` and `+00:00` offsets and
/// carry zero to nine fractional digits.
func parseISODate(_ raw: String) -> Date? {
    var s = raw
    var fraction = 0.0
    if let dot = s.firstIndex(of: ".") {
        var end = s.index(after: dot)
        while end < s.endIndex, s[end].isNumber { end = s.index(after: end) }
        fraction = Double("0" + s[dot..<end]) ?? 0
        s.removeSubrange(dot..<end)
    }
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    guard let base = f.date(from: s) else { return nil }
    return base.addingTimeInterval(fraction)
}
