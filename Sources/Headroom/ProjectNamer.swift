import Foundation

/// Turns a session's workspace into a short project name.
///
/// Order: the GitHub repo name from the folder's git `origin` (worktrees
/// resolve to their main repo), then patterns for folders that no longer
/// exist (T3 and Claude worktrees), then the folder name.
enum ProjectNamer {
    private static var cache: [String: String] = [:]
    private static let lock = NSLock()

    static func name(workspace: String?, path: String?, home: String = NSHomeDirectory()) -> String {
        let key = (path ?? "") + "|" + (workspace ?? "")
        if let hit = lock.withLock({ cache[key] }) { return hit }
        let result = resolve(workspace: workspace, path: path, home: home)
        lock.withLock { cache[key] = result }
        return result
    }

    static func resolve(workspace: String?, path: String?, home: String) -> String {
        let raw = [path, workspace].compactMap { $0 }.first { !$0.isEmpty }
        guard let raw else { return "No project" }

        if raw.hasPrefix("/") {
            if raw.contains("/OpenBot/Agents/") { return "OpenBot agent" }
            if let repo = gitRepoName(startingAt: raw, home: home) { return repo }
            if raw == home { return "~" }
            let parent = (raw as NSString).deletingLastPathComponent
            if parent == home { return "~/" + (raw as NSString).lastPathComponent }
            return (raw as NSString).lastPathComponent
        }
        if raw.hasPrefix("-") { return fromSlug(raw, home: home) }
        return raw
    }

    /// Claude Code stores the folder as a slug: every "/" and "." becomes "-".
    static func fromSlug(_ slug: String, home: String) -> String {
        // ~/.t3/worktrees/<repo>/t3-<hash>
        if let m = slug.firstMatch(of: #/-t3-worktrees-(.+?)-t3-[0-9a-f]{6,}$/#) { return String(m.1) }
        // <repo>/.claude/worktrees/<name>
        if let m = slug.firstMatch(of: #/^(.+?)--claude-worktrees-.+$/#) {
            return String(m.1.split(separator: "-").last ?? m.1)
        }
        if slug.contains("-OpenBot-Agents-") { return "OpenBot agent" }
        let homeSlug = home.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ".", with: "-")
        if slug.lowercased() == homeSlug.lowercased() { return "~" }
        let rest = slug.lowercased().hasPrefix(homeSlug.lowercased() + "-")
            ? String(slug.dropFirst(homeSlug.count + 1)) : nil
        if let rest, !rest.contains("-") { return "~/" + rest.lowercased() }
        return String(slug.split(separator: "-").last ?? Substring(slug))
    }

    /// Walks up to the nearest git folder and returns the repo's name from its
    /// `origin` URL, or the repo folder's name when there is no remote.
    static func gitRepoName(startingAt path: String, home: String) -> String? {
        let fm = FileManager.default
        var dir = path
        for _ in 0..<10 {
            let dotGit = (dir as NSString).appendingPathComponent(".git")
            var isDir: ObjCBool = false
            if fm.fileExists(atPath: dotGit, isDirectory: &isDir) {
                let gitDir = isDir.boolValue ? dotGit : mainGitDir(fromWorktreeFile: dotGit)
                guard let gitDir else { return (dir as NSString).lastPathComponent }
                if let url = originURL(configAt: (gitDir as NSString).appendingPathComponent("config")),
                   let name = repoName(fromRemote: url) {
                    return name
                }
                // No remote: name the main repo folder, not the worktree folder.
                return ((gitDir as NSString).deletingLastPathComponent as NSString).lastPathComponent
            }
            if dir == home || dir == "/" { break }
            dir = (dir as NSString).deletingLastPathComponent
        }
        return nil
    }

    /// A worktree's `.git` is a file: "gitdir: <repo>/.git/worktrees/<name>".
    private static func mainGitDir(fromWorktreeFile file: String) -> String? {
        guard let text = try? String(contentsOfFile: file, encoding: .utf8),
              let line = text.split(separator: "\n").first(where: { $0.hasPrefix("gitdir:") }) else { return nil }
        let worktreeGitDir = line.dropFirst("gitdir:".count).trimmingCharacters(in: .whitespaces)
        // <repo>/.git/worktrees/<name> → <repo>/.git
        let parent = (worktreeGitDir as NSString).deletingLastPathComponent
        if (parent as NSString).lastPathComponent == "worktrees" {
            return (parent as NSString).deletingLastPathComponent
        }
        return worktreeGitDir
    }

    private static func originURL(configAt path: String) -> String? {
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return nil }
        var inOrigin = false
        for raw in text.split(separator: "\n") {
            let line = raw.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix("[") { inOrigin = line == "[remote \"origin\"]"; continue }
            if inOrigin, line.hasPrefix("url") {
                return line.split(separator: "=", maxSplits: 1).last.map { $0.trimmingCharacters(in: .whitespaces) }
            }
        }
        return nil
    }

    /// "git@github.com:me/repo.git" or "https://github.com/me/repo" → "repo".
    static func repoName(fromRemote url: String) -> String? {
        let last = url.split(whereSeparator: { $0 == "/" || $0 == ":" }).last.map(String.init) ?? ""
        let name = last.hasSuffix(".git") ? String(last.dropLast(4)) : last
        return name.isEmpty ? nil : name
    }
}
