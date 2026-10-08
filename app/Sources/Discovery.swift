import Foundation

/// Finds Claude Code sessions from their transcripts, so sessions that were already open before
/// Wigglet connected (or that never fired a hook since) still show up. Hook files win over this.
struct Discovered {
    let sid: String
    let path: String
    let cwd: String
    let title: String
    let entrypoint: String
    let created: Double   // ms
    let modified: Double  // ms
}

/// How long a session can sit untouched before it leaves the team. Minutes; 0 means never.
enum HideAfter {
    static let options: [(Int, String)] = [(30, "30m"), (60, "1h"), (180, "3h"), (480, "8h"), (1440, "1d")]
    static var minutes: Int {
        get { let v = UserDefaults.standard.integer(forKey: "hideAfter"); return v == 0 ? 180 : v }
        set { UserDefaults.standard.set(newValue, forKey: "hideAfter") }
    }
    static var ms: Double { Double(minutes) * 60_000 }
}

final class TranscriptDiscovery {
    let root: String
    private var cache: [String: (mtime: Double, info: Discovered?)] = [:]
    private var lastScan = Date.distantPast
    private var last: [Discovered] = []

    /// Rescan on the next call (after the cutoff changes).
    func invalidate() { lastScan = .distantPast }

    init(root: String = homeDir + "/.claude/projects") { self.root = root }

    /// Recently modified top-level transcripts. Sub-agent transcripts live in subfolders and are skipped.
    /// Scans at most every `every` seconds; parses a file only when its mtime changes.
    func scan(maxAgeMs: Double, every: TimeInterval = 4) -> [Discovered] {
        if Date().timeIntervalSince(lastScan) < every { return last }
        lastScan = Date()
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970 * 1000
        var out: [Discovered] = []
        var seen = Set<String>()
        for dir in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            let dirPath = root + "/" + dir
            for f in (try? fm.contentsOfDirectory(atPath: dirPath)) ?? [] where f.hasSuffix(".jsonl") {
                let path = dirPath + "/" + f
                guard let attrs = try? fm.attributesOfItem(atPath: path),
                      let mdate = attrs[.modificationDate] as? Date else { continue }
                let mtime = mdate.timeIntervalSince1970 * 1000
                if now - mtime > maxAgeMs { continue }
                seen.insert(path)
                if let c = cache[path], c.mtime == mtime { if let i = c.info { out.append(i) }; continue }
                let created = ((attrs[.creationDate] as? Date) ?? mdate).timeIntervalSince1970 * 1000
                let info = Self.parse(path: path, sid: String(f.dropLast(6)), created: created, modified: mtime)
                cache[path] = (mtime, info)
                if let info { out.append(info) }
            }
        }
        cache = cache.filter { seen.contains($0.key) }
        last = out
        return out
    }

    /// Reads the last 64 KB for cwd, entrypoint and title. Skips headless `claude -p` runs (Wigglet's own chat included).
    static func parse(path: String, sid: String, created: Double, modified: Double) -> Discovered? {
        guard isSafeSid(sid), let h = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 65_536 ? size - 65_536 : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        var cwd = "", entry = "", title = ""
        for line in text.split(separator: "\n").reversed() {
            guard let o = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { continue }
            if (o["isSidechain"] as? Bool) == true { continue }
            if cwd.isEmpty, let v = o["cwd"] as? String { cwd = v }
            if entry.isEmpty, let v = o["entrypoint"] as? String { entry = v }
            if title.isEmpty, let v = o["customTitle"] as? String { title = v }
            if !cwd.isEmpty && !entry.isEmpty && !title.isEmpty { break }
        }
        if cwd.isEmpty || entry == "sdk-cli" || entry == "sdk-ts" || entry == "sdk-py" { return nil }
        return Discovered(sid: sid, path: path, cwd: cwd, title: title, entrypoint: entry, created: created, modified: modified)
    }

    /// Where a session runs, from its transcript's entrypoint. Terminal sessions have no app to name.
    static func host(for entrypoint: String) -> (bundle: String, app: String) {
        switch entrypoint {
        case "claude-desktop": return ("com.anthropic.claudefordesktop", "Claude")
        case "claude-vscode", "vscode": return ("com.microsoft.VSCode", "VS Code")
        default: return ("", "")
        }
    }
}

/// Session ids become file names; allow only what Claude Code generates.
func isSafeSid(_ sid: String) -> Bool {
    !sid.isEmpty && sid.count <= 128 && sid.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
}

extension TranscriptDiscovery {
    /// Selftest: a desktop transcript is found, a headless `-p` one and a stale one are not.
    static func selfCheck() -> String? {
        let root = homeDir + "/.claude/projects-selftest"
        let fm = FileManager.default
        try? fm.removeItem(atPath: root)
        try? fm.createDirectory(atPath: root + "/-p", withIntermediateDirectories: true)
        defer { try? fm.removeItem(atPath: root) }
        func write(_ sid: String, _ entry: String, age: TimeInterval) {
            let lines = [#"{"type":"user","cwd":"/tmp/proj","entrypoint":"\#(entry)","sessionId":"\#(sid)"}"#,
                         #"{"type":"custom-title","customTitle":"My work","sessionId":"\#(sid)"}"#,
                         "not json"]
            let path = root + "/-p/" + sid + ".jsonl"
            fm.createFile(atPath: path, contents: Data(lines.joined(separator: "\n").utf8))
            try? fm.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: path)
        }
        write("desk-1", "claude-desktop", age: 60)
        write("head-1", "sdk-cli", age: 60)
        write("old-1", "cli", age: 7200)
        let found = TranscriptDiscovery(root: root).scan(maxAgeMs: 3_600_000)
        guard found.count == 1, let d = found.first else { return "discovery count \(found.map(\.sid))" }
        if d.sid != "desk-1" || d.cwd != "/tmp/proj" || d.title != "My work" { return "discovery fields" }
        if host(for: d.entrypoint).bundle != "com.anthropic.claudefordesktop" { return "discovery host" }
        return nil
    }
}
