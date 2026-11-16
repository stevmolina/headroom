import Foundation

/// Runs the tokscale CLI and decodes its JSON. Every call runs on a background
/// thread; nothing here touches the main actor.
struct Tokscale: Sendable {
    enum Failure: LocalizedError {
        case notFound
        case timedOut(String)
        case crashed(String)
        case exit(Int32, String)
        case decode(String, String)

        var errorDescription: String? {
            switch self {
            case .notFound:
                return "tokscale not found. Install it to ~/.local/bin or set HEADROOM_TOKSCALE."
            case .timedOut(let cmd):
                return "tokscale \(cmd) timed out"
            case .crashed(let cmd):
                return "tokscale \(cmd) crashed"
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
            "\(home)/.bun/bin/tokscale",
            "\(home)/.npm-global/bin/tokscale",
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
                continuation.resume(with: Self.runBlocking(executable, args, timeout: timeout))
            }
        }
    }

    /// Runs one process to completion or to its deadline. Always returns, even
    /// when the process ignores SIGTERM or a grandchild keeps a pipe open.
    private static func runBlocking(_ executable: URL, _ args: [String], timeout: TimeInterval) -> Result<Data, Error> {
        let command = args.first ?? ""
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
        // Set before run() so a process that exits at once still signals.
        let exited = DispatchSemaphore(value: 0)
        process.terminationHandler = { _ in exited.signal() }

        do {
            try process.run()
        } catch {
            try? out.fileHandleForWriting.close()
            try? err.fileHandleForWriting.close()
            return .failure(error)
        }

        // Drain both pipes while the process runs so a large report never
        // blocks on a full pipe buffer.
        let buffers = Buffers()
        let readers = DispatchGroup()
        readers.enter()
        DispatchQueue.global().async {
            buffers.setOut(out.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }
        readers.enter()
        DispatchQueue.global().async {
            buffers.setErr(err.fileHandleForReading.readDataToEndOfFile())
            readers.leave()
        }

        var timedOut = false
        if exited.wait(timeout: .now() + timeout) == .timedOut {
            timedOut = true
            process.terminate()
            if exited.wait(timeout: .now() + 3) == .timedOut {
                kill(process.processIdentifier, SIGKILL)
                _ = exited.wait(timeout: .now() + 2)
            }
        }
        // A grandchild can hold the pipes open after tokscale exits; give the
        // readers a moment, then stop waiting for them.
        if readers.wait(timeout: .now() + 3) == .timedOut {
            try? out.fileHandleForReading.close()
            try? err.fileHandleForReading.close()
            if !timedOut { return .failure(Failure.timedOut(command)) }
        }

        if timedOut { return .failure(Failure.timedOut(command)) }
        if process.isRunning { return .failure(Failure.timedOut(command)) }
        if process.terminationReason == .uncaughtSignal { return .failure(Failure.crashed(command)) }
        if process.terminationStatus != 0 {
            return .failure(Failure.exit(process.terminationStatus, String(decoding: buffers.err, as: UTF8.self)))
        }
        return .success(buffers.out)
    }

    /// Output collected by the reader threads.
    private final class Buffers: @unchecked Sendable {
        private let lock = NSLock()
        private var _out = Data()
        private var _err = Data()
        var out: Data { lock.withLock { _out } }
        var err: Data { lock.withLock { _err } }
        func setOut(_ d: Data) { lock.withLock { _out = d } }
        func setErr(_ d: Data) { lock.withLock { _err = d } }
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
/// carry zero to nine fractional digits. A timestamp with no zone is read as UTC.
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
    if let base = f.date(from: s) { return base.addingTimeInterval(fraction) }
    if let base = f.date(from: s + "Z") { return base.addingTimeInterval(fraction) }
    return nil
}
