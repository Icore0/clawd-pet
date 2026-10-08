import Foundation

// Two jobs:
//  1. `--hook`: called by Claude Code hooks, turns the event JSON on stdin into a per-session state file.
//  2. install/remove those hooks in ~/.claude/settings.json (only when the user asks).

let settingsPath = homeDir + "/.claude/settings.json"

func activityName(tool: String, input: [String: Any], previousTool: String, toolTimes: [Double], now: Double) -> String {
    if tool == "WebSearch" { return "webSearch" }
    if tool == "WebFetch" { return "webFetch" }
    if tool == "NotebookEdit" { return "notebook" }
    if tool.hasPrefix("mcp__") { return "mcp" }
    if tool == "Read" {
        let recent = toolTimes.filter { now - $0 <= 5_000 }
        if previousTool == "Read" && recent.count >= 3 { return "burstRead" }
        return "read"
    }
    let cmd = ((input["command"] as? String) ?? "").lowercased()
    if cmd.isEmpty { return "" }
    // Match the program and its subcommand, not a later argument. `echo vercel` and `git commit-tree` stay unmatched.
    let parts = cmd.replacingOccurrences(of: "&&", with: "\n").replacingOccurrences(of: "||", with: "\n")
        .replacingOccurrences(of: ";", with: "\n").replacingOccurrences(of: "|", with: "\n")
    for line in parts.split(separator: "\n") {
        let argv = line.split(whereSeparator: { $0 == " " || $0 == "\t" }).map(String.init)
        guard let head = argv.first, !head.isEmpty else { continue }
        if head == "vercel" || head == "netlify" { return "deploy" }
        if argv.count >= 2 && head == "fly" && argv[1] == "deploy" { return "deploy" }
        if argv.count >= 2 && head == "npm" && argv[1] == "publish" { return "deploy" }
        if argv.count >= 2 && head == "docker" && argv[1] == "push" { return "deploy" }
        if argv.count >= 2 && head == "git" && argv[1] == "commit" { return "commit" }
        if argv.count >= 2 && head == "git" && argv[1] == "push" { return "push" }
        if argv.count >= 2 && head == "git" && (argv[1] == "pull" || argv[1] == "fetch") { return "pull" }
        if head == "eslint" || head == "prettier" || head == "ruff" { return "lint" }
        if head == "npx", let tool = argv.dropFirst().first, tool == "eslint" || tool == "prettier" || tool == "ruff" { return "lint" }
        if head == "prisma" || head == "alembic" || head == "psql" { return "migrate" }
        if head == "docker" || head == "compose" || head == "docker-compose" { return "docker" }
        if head == "uvicorn" { return "serve" }
        if argv.count >= 3 && head == "npm" && argv[1] == "run" && argv[2] == "dev" { return "serve" }
    }
    return ""
}
let hookEvents = ["SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse", "PostToolUseFailure", "Notification", "Stop", "StopFailure", "SubagentStart", "SubagentStop", "PreCompact", "PostCompact", "PermissionDenied"]

func runHookMode() -> Never {
    let data = FileHandle.standardInput.readDataToEndOfFile()
    guard let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { exit(0) }
    let ev = (o["hook_event_name"] as? String) ?? ""
    let sid = (o["session_id"] as? String) ?? "unknown"
    let project = (((o["cwd"] as? String) ?? "") as NSString).lastPathComponent
    let input = (o["tool_input"] as? [String: Any]) ?? [:]
    func base(_ k: String) -> String { ((input[k] as? String) ?? "").split(separator: "/").last.map(String.init) ?? "" }

    let tool = (o["tool_name"] as? String) ?? ""
    var mood = "working", kind = "think", say = "", delta = ""
    var raiseAlarm = false
    switch ev {
    case "SessionStart": mood = "hello"; kind = "hello"; say = ""
    case "SessionEnd": mood = "bye"; kind = "bye"; say = ""
    case "UserPromptSubmit": break
    case "PostToolUse", "PostToolUseFailure", "SubagentStop", "SubagentStart": break
    case "PreCompact", "PostCompact": kind = "compact"; say = "context"
    case "Stop": mood = "done"; kind = "none"; say = ""
    case "StopFailure": raiseAlarm = true
    case "PermissionDenied": mood = "waiting"; kind = "ask"; say = ""
    case "Notification":
        let msg = ((o["message"] as? String) ?? "").lowercased()
        if msg.contains("quota") { raiseAlarm = true }
        mood = "waiting"
        if msg.contains("permission") || msg.contains("approve") || msg.contains("allow") { kind = "ask"; say = msg.replacingOccurrences(of: "claude needs your permission to use ", with: "") }
        else { kind = "yourTurn"; say = "" }
    case "PreToolUse":
        func lines(_ s: String) -> Int { s.isEmpty ? 0 : s.split(separator: "\n", omittingEmptySubsequences: false).count }
        switch tool {
        case "Read": kind = "read"; say = base("file_path")
        case "Edit":
            kind = "edit"; say = base("file_path")
            let n = lines((input["new_string"] as? String) ?? ""), d = lines((input["old_string"] as? String) ?? "")
            delta = "+\(n) −\(d)"
        case "MultiEdit":
            kind = "edit"; say = base("file_path")
            let es = (input["edits"] as? [[String: Any]]) ?? []
            delta = "+\(es.reduce(0) { $0 + lines(($1["new_string"] as? String) ?? "") }) −\(es.reduce(0) { $0 + lines(($1["old_string"] as? String) ?? "") })"
        case "Write": kind = "edit"; say = base("file_path"); delta = "+\(lines((input["content"] as? String) ?? ""))"
        case "NotebookEdit": kind = "edit"; say = base("notebook_path")
        case "Bash":
            let cmd = ((input["command"] as? String) ?? "").lowercased()
            let desc = (input["description"] as? String) ?? ""
            func has(_ ws: [String]) -> Bool { ws.contains { cmd.contains($0) } }
            if cmd.hasPrefix("git ") || cmd.contains(" git ") || cmd.contains("&& git") { kind = "git"; say = desc.isEmpty ? "git" : desc }
            else if has(["test", "pytest", "jest", "vitest", "rspec"]) { kind = "test"; say = desc.isEmpty ? "running tests" : desc }
            else if has(["install", "npm i ", "yarn add", "pnpm add", "brew ", "pip "]) { kind = "install"; say = desc.isEmpty ? "installing" : desc }
            else if has(["build", "make", "compile", "xcodebuild", "tsc", "swiftc", "cargo"]) { kind = "build"; say = desc.isEmpty ? "building" : desc }
            else { kind = "bash"; say = desc.isEmpty ? "shell command" : desc }
        case "Grep": kind = "search"; say = (input["pattern"] as? String).map { "“\($0.prefix(26))”" } ?? "searching"
        case "Glob": kind = "search"; say = (input["pattern"] as? String).map { String($0.prefix(30)) } ?? "files"
        case "WebFetch": kind = "web"; say = ((input["url"] as? String).flatMap { URL(string: $0)?.host }) ?? "a web page"
        case "WebSearch": kind = "web"; say = (input["query"] as? String).map { String($0.prefix(30)) } ?? "the web"
        case "Task", "Agent": kind = "agent"; say = (input["description"] as? String) ?? "a helper"
        case "TodoWrite": kind = "plan"; say = "todo list"
        default: kind = "think"; say = tool.hasPrefix("mcp__") ? (tool.split(separator: "_").last.map(String.init) ?? "a tool") : tool
        }
    default: exit(0)
    }
    let path = sessionsDir + "/" + sid.replacingOccurrences(of: "/", with: "_") + ".json"
    if ev == "SessionEnd" {
        try? FileManager.default.removeItem(atPath: path)
        exit(0)
    }
    var prev: [String: Any] = [:]
    if let d = FileManager.default.contents(atPath: path),
       let p = try? JSONSerialization.jsonObject(with: d) as? [String: Any] { prev = p }
    func num(_ k: String) -> Double? { (prev[k] as? NSNumber)?.doubleValue }
    let now = Date().timeIntervalSince1970 * 1000
    let startedAt = num("startedAt") ?? now
    var errorStreak = (prev["errorStreak"] as? NSNumber)?.intValue ?? 0
    var lastErrorAt: Any = num("lastErrorAt").map { $0 as Any } ?? NSNull()
    var activityId = (prev["activityId"] as? String) ?? ""
    var subagentCount = (prev["subagentCount"] as? NSNumber)?.intValue ?? 0
    var lastDurationMs = (prev["lastDurationMs"] as? NSNumber)?.doubleValue ?? 0
    var toolStartedAt: Any = num("toolStartedAt").map { $0 as Any } ?? NSNull()
    var toolTimes: [Double] = ((prev["toolTimes"] as? [Any]) ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    let previousTool = (prev["lastTool"] as? String) ?? ""
    if ev == "PreToolUse" {
        toolTimes.append(now)
        toolTimes = Array(toolTimes.filter { now - $0 <= 10_000 }.suffix(20))
        toolStartedAt = now
        activityId = activityName(tool: tool, input: input, previousTool: previousTool, toolTimes: toolTimes, now: now)
    }
    if ev == "PostToolUse" || ev == "PostToolUseFailure" {
        toolStartedAt = NSNull()
        if let ms = (o["duration_ms"] as? NSNumber)?.doubleValue { lastDurationMs = ms }
    }
    if ev == "PostToolUse" {
        errorStreak = 0
        activityId = ""
    }
    if ev == "PostToolUseFailure" {
        let interrupt = (o["is_interrupt"] as? Bool) ?? (o["is_interrupt"] as? NSNumber)?.boolValue ?? false
        if !interrupt {
            errorStreak += 1
            lastErrorAt = now
        }
        let err = (o["error"] as? String) ?? ""
        let stdout = ((o["tool_response"] as? [String: Any])?["stdout"] as? String) ?? ""
        if err.contains("CONFLICT") || err.contains("Automatic merge failed") || stdout.contains("CONFLICT") || stdout.contains("Automatic merge failed") {
            activityId = "conflict"
        } else {
            activityId = ""
        }
    }
    if ev == "SubagentStart" {
        subagentCount += 1
        if let m = prev["mood"] as? String { mood = m }
        if let k = prev["kind"] as? String { kind = k }
        if let s = prev["say"] as? String { say = s }
        if let d = prev["delta"] as? String { delta = d }
    }
    if ev == "SubagentStop" { subagentCount = max(0, subagentCount - 1) }
    if raiseAlarm {
        activityId = "alarm"
        if ev == "StopFailure" {
            if let m = prev["mood"] as? String { mood = m }
            if let k = prev["kind"] as? String { kind = k }
            if let s = prev["say"] as? String { say = s }
            if let d = prev["delta"] as? String { delta = d }
        }
    }
    let prevMood = (prev["mood"] as? String) ?? ""
    let lastTool: String
    let toolCount: Int
    if ev == "PreToolUse" {
        lastTool = tool
        toolCount = ((prev["toolCount"] as? NSNumber)?.intValue ?? 0) + 1
    } else {
        lastTool = (prev["lastTool"] as? String) ?? ""
        toolCount = (prev["toolCount"] as? NSNumber)?.intValue ?? 0
    }
    let turnStart: Any
    if mood == "working" {
        if prevMood != "working" { turnStart = now }
        else { turnStart = num("turnStart").map { $0 as Any } ?? NSNull() }
    } else { turnStart = NSNull() }
    try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
    let obj: [String: Any] = [
        "sid": sid,
        "cwd": (o["cwd"] as? String) ?? "",
        "project": project,
        "startedAt": startedAt,
        "transcript": (o["transcript_path"] as? String) ?? "",
        "lastTool": lastTool,
        "toolCount": toolCount,
        "turnStart": turnStart,
        "errorStreak": errorStreak,
        "lastErrorAt": lastErrorAt,
        "activityId": activityId,
        "subagentCount": subagentCount,
        "lastDurationMs": lastDurationMs,
        "toolStartedAt": toolStartedAt,
        "toolTimes": toolTimes,
        "mood": mood,
        "kind": kind,
        "say": say,
        "delta": delta,
        "ts": now
    ]
    if let d = try? JSONSerialization.data(withJSONObject: obj) {
        try? d.write(to: URL(fileURLWithPath: path), options: .atomic)
    }
    exit(0)
}

enum HookInstaller {
    static var command: String {
        let exe = Bundle.main.executablePath ?? CommandLine.arguments[0]
        return "[ -x '\(exe)' ] && '\(exe)' --hook; exit 0"
    }
    static func isOurs(_ c: String) -> Bool { c.contains("--hook") && (c.contains("ClawdPet") || c.contains("Familiar")) }

    static func load() -> [String: Any]? {
        guard let d = FileManager.default.contents(atPath: settingsPath) else { return [:] }
        return (try? JSONSerialization.jsonObject(with: d)) as? [String: Any]
    }
    static func save(_ s: [String: Any]) throws {
        let fm = FileManager.default
        let backup = settingsPath + ".clawd-backup"
        if fm.fileExists(atPath: settingsPath), !fm.fileExists(atPath: backup) { try? fm.copyItem(atPath: settingsPath, toPath: backup) }
        try fm.createDirectory(atPath: (settingsPath as NSString).deletingLastPathComponent, withIntermediateDirectories: true)
        let d = try JSONSerialization.data(withJSONObject: s, options: [.prettyPrinted, .withoutEscapingSlashes])
        try d.write(to: URL(fileURLWithPath: settingsPath), options: .atomic)
    }
    static func strip(_ hooks: inout [String: Any]) {
        for (ev, v) in hooks {
            guard let groups = v as? [[String: Any]] else { continue }
            let kept = groups.compactMap { g -> [String: Any]? in
                var g = g
                let hs = (g["hooks"] as? [[String: Any]] ?? []).filter { !isOurs(($0["command"] as? String) ?? "") }
                if hs.isEmpty { return nil }
                g["hooks"] = hs; return g
            }
            if kept.isEmpty { hooks.removeValue(forKey: ev) } else { hooks[ev] = kept }
        }
    }
    static var isInstalled: Bool {
        guard let s = load(), let hooks = s["hooks"] as? [String: Any] else { return false }
        return hooks.values.contains { v in
            ((v as? [[String: Any]]) ?? []).contains { g in ((g["hooks"] as? [[String: Any]]) ?? []).contains { isOurs(($0["command"] as? String) ?? "") } }
        }
    }
    static func install() throws {
        guard var s = load() else { throw NSError(domain: PRODUCT_NAME, code: 1, userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json isn't valid JSON, so I left it alone."]) }
        var hooks = (s["hooks"] as? [String: Any]) ?? [:]
        strip(&hooks)
        for ev in hookEvents {
            var group: [String: Any] = ["hooks": [["type": "command", "command": command, "timeout": 5]]]
            if ev == "PreToolUse" || ev == "PostToolUse" || ev == "PostToolUseFailure" { group["matcher"] = "*" }
            var groups = (hooks[ev] as? [[String: Any]]) ?? []
            groups.append(group); hooks[ev] = groups
        }
        s["hooks"] = hooks
        try save(s)
    }
    static func remove() throws {
        guard var s = load() else { return }
        var hooks = (s["hooks"] as? [String: Any]) ?? [:]
        strip(&hooks)
        if hooks.isEmpty { s.removeValue(forKey: "hooks") } else { s["hooks"] = hooks }
        try save(s)
    }
}
