import Foundation
import Security

// Chat backends. Rules: API keys live only in the Keychain (one item per provider), never in
// UserDefaults, files or logs, and are redacted from every error string.

enum Provider: String, CaseIterable, Identifiable {
    case claude, anthropic, openai, openrouter, gemini, ollama
    var id: String { rawValue }

    var label: String {
        switch self {
        case .claude: return "Claude Code"
        case .anthropic: return "Anthropic"
        case .openai: return "OpenAI"
        case .openrouter: return "OpenRouter"
        case .gemini: return "Gemini"
        case .ollama: return "Ollama"
        }
    }
    var detail: String {
        switch self {
        case .claude: return "Uses the claude command you already have. No key; counts toward your Claude plan."
        case .anthropic: return "Claude through the Anthropic API with your own key."
        case .openai: return "OpenAI API with your own key."
        case .openrouter: return "One key for hundreds of models."
        case .gemini: return "Google Gemini API with your own key."
        case .ollama: return "A model running on this Mac. Nothing leaves your machine."
        }
    }
    var needsKey: Bool { self != .claude && self != .ollama }
    var keyHint: String {
        switch self {
        case .anthropic: return "sk-ant-…"
        case .openai: return "sk-…"
        case .openrouter: return "sk-or-…"
        case .gemini: return "AIza…"
        default: return ""
        }
    }
    var defaultModel: String {
        switch self {
        case .claude: return ""
        case .anthropic: return "claude-haiku-5-5"
        case .openai: return "gpt-5-mini"
        case .openrouter: return "anthropic/claude-haiku-4.5"
        case .gemini: return "gemini-2.5-flash"
        case .ollama: return "llama3.2"
        }
    }
    var defaultBase: String {
        switch self {
        case .claude: return ""
        case .anthropic: return "https://api.anthropic.com/v1/messages"
        case .openai: return "https://api.openai.com/v1/chat/completions"
        case .openrouter: return "https://openrouter.ai/api/v1/chat/completions"
        case .gemini: return "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions"
        case .ollama: return "http://localhost:11434/v1/chat/completions"
        }
    }
    /// Endpoints are fixed. Tests may point them at a mock server, and only when HOME is a temp dir,
    /// so a real key can never be redirected.
    var endpoint: String {
        let env = ProcessInfo.processInfo.environment
        let home = env["HOME"] ?? ""
        if home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/"), let o = env["WIGGLET_API_BASE"], !o.isEmpty { return o }
        return defaultBase
    }

    static var current: Provider {
        get {
            if let raw = UserDefaults.standard.string(forKey: "provider"), let p = Provider(rawValue: raw) { return p }
            // 1.0 had only OpenRouter or the CLI.
            return KeychainStore.load(.openrouter) != nil && !UserDefaults.standard.bool(forKey: "useClaudeCLI") ? .openrouter : .claude
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "provider") }
    }
    var model: String {
        get { let m = UserDefaults.standard.string(forKey: "model." + rawValue) ?? ""; return m.isEmpty ? defaultModel : m }
        nonmutating set { UserDefaults.standard.set(newValue.trimmingCharacters(in: .whitespacesAndNewlines), forKey: "model." + rawValue) }
    }
    var hasKey: Bool { !needsKey || KeychainStore.load(self) != nil }
}

enum KeychainStore {
    static var service: String { Bundle.main.bundleIdentifier ?? "dev.wigglet.app" }

    private static func query(_ p: Provider) -> [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: p.rawValue]
    }
    static func save(_ key: String, for p: Provider) -> Bool {
        let q = query(p)
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = Data(key.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func load(_ p: Provider) -> String? {
        var q = query(p)
        q[kSecReturnData as String] = true
        q[kSecMatchLimit as String] = kSecMatchLimitOne
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }
    @discardableResult static func delete(_ p: Provider) -> Bool {
        let r = SecItemDelete(query(p) as CFDictionary)
        return r == errSecSuccess || r == errSecItemNotFound
    }
}

struct ChatMessage { var role: String; var content: String }   // role: system | user | assistant

enum ChatError: Error {
    case noKey, badKey, noCredits, rateLimited, offline, timeout, server(Int), other
    func message(_ p: Provider) -> String {
        switch self {
        case .noKey: return "Add your \(p.label) key in Settings → Chat."
        case .badKey: return "\(p.label) rejected the key. Check it in Settings → Chat."
        case .noCredits: return "Out of \(p.label) credits."
        case .rateLimited: return "Rate limited. Try again in a moment."
        case .offline: return p == .ollama ? "Ollama isn't running. Start it with `ollama serve`." : "No connection."
        case .timeout: return "That took too long. Try again."
        case .server(let c): return c == 404 ? "\(p.label) doesn't know the model “\(p.model)”." : "\(p.label) error (\(c))."
        case .other: return "Something went wrong."
        }
    }
}

enum ChatAPI {
    static func redact(_ s: String, key: String) -> String {
        key.isEmpty ? s : s.replacingOccurrences(of: key, with: "[key]")
    }

    static func map(status: Int) -> ChatError {
        switch status {
        case 401, 403: return .badKey
        case 402: return .noCredits
        case 429: return .rateLimited
        default: return .server(status)
        }
    }
    static func map(error: Error) -> ChatError {
        if let e = error as? ChatError { return e }
        let c = error as NSError
        guard c.domain == NSURLErrorDomain else { return .other }
        switch c.code {
        case NSURLErrorTimedOut: return .timeout
        case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost,
             NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed: return .offline
        default: return .other
        }
    }

    /// One SSE line from an OpenAI-style stream. Returns (delta, costUSD, done).
    static func parseOpenAI(line: String) -> (String?, Double?, Bool) {
        guard line.hasPrefix("data:") else { return (nil, nil, false) }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return (nil, nil, true) }
        guard let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, nil, false) }
        var delta: String?
        if let ch = (o["choices"] as? [[String: Any]])?.first, let dl = ch["delta"] as? [String: Any], let t = dl["content"] as? String, !t.isEmpty { delta = t }
        let cost = ((o["usage"] as? [String: Any])?["cost"] as? NSNumber)?.doubleValue
        return (delta, cost, false)
    }

    /// One SSE line from the Anthropic Messages stream. Returns (delta, done).
    static func parseAnthropic(line: String) -> (String?, Bool) {
        guard line.hasPrefix("data:") else { return (nil, false) }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        guard let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, false) }
        switch o["type"] as? String {
        case "content_block_delta":
            let t = (o["delta"] as? [String: Any])?["text"] as? String
            return (t?.isEmpty == false ? t : nil, false)
        case "message_stop": return (nil, true)
        default: return (nil, false)
        }
    }

    static func request(_ p: Provider, messages: [ChatMessage], key: String) -> URLRequest? {
        guard let url = URL(string: p.endpoint) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: 60)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        var body: [String: Any] = ["model": p.model, "stream": true]
        let recent = messages.suffix(20)
        if p == .anthropic {
            req.setValue(key, forHTTPHeaderField: "x-api-key")
            req.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
            let system = recent.filter { $0.role == "system" }.map(\.content).joined(separator: "\n\n")
            if !system.isEmpty { body["system"] = system }
            body["max_tokens"] = 1024
            body["messages"] = recent.filter { $0.role != "system" }.map { ["role": $0.role, "content": $0.content] }
        } else {
            if !key.isEmpty { req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization") }
            if p == .openrouter {
                req.setValue("https://github.com/Icore0/wigglet", forHTTPHeaderField: "HTTP-Referer")
                req.setValue("Wigglet", forHTTPHeaderField: "X-Title")
                body["usage"] = ["include": true]
            }
            body["messages"] = recent.map { ["role": $0.role, "content": $0.content] }
        }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }

    /// Streams a reply from an HTTP provider. Callbacks run on the main thread.
    @discardableResult
    static func stream(_ p: Provider, messages: [ChatMessage],
                       onDelta: @escaping (String) -> Void, onCost: @escaping (Double) -> Void,
                       onDone: @escaping (Result<Void, ChatError>) -> Void) -> Task<Void, Never> {
        Task {
            func finish(_ r: Result<Void, ChatError>) { DispatchQueue.main.async { onDone(r) } }
            let key = p.needsKey ? (KeychainStore.load(p) ?? "") : ""
            if p.needsKey && key.isEmpty { return finish(.failure(.noKey)) }
            guard let req = request(p, messages: messages, key: key) else { return finish(.failure(.other)) }
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                if let h = resp as? HTTPURLResponse, h.statusCode != 200 { return finish(.failure(map(status: h.statusCode))) }
                var got = false
                for try await line in bytes.lines {
                    if Task.isCancelled { return finish(.failure(.other)) }
                    let delta: String?, cost: Double?, done: Bool
                    if p == .anthropic { (delta, done) = parseAnthropic(line: line); cost = nil }
                    else { (delta, cost, done) = parseOpenAI(line: line) }
                    if let d = delta { got = true; DispatchQueue.main.async { onDelta(d) } }
                    if let c = cost { DispatchQueue.main.async { onCost(c) } }
                    if done { break }
                }
                finish(got ? .success(()) : .failure(.other))
            } catch {
                finish(.failure(map(error: error)))
            }
        }
    }

    /// The `claude` executable. GUI apps don't get the shell PATH, so look in the usual places,
    /// then ask a login shell (a fixed command, nothing interpolated).
    static func claudePath() -> String? {
        let fm = FileManager.default
        for c in [homeDir + "/.local/bin/claude", homeDir + "/.claude/local/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude"]
        where fm.isExecutableFile(atPath: c) { return c }
        let p = Process(), out = Pipe()
        p.executableURL = URL(fileURLWithPath: "/bin/zsh")
        p.arguments = ["-lc", "command -v claude"]
        p.standardOutput = out; p.standardError = Pipe()
        guard (try? p.run()) != nil else { return nil }
        p.waitUntilExit()
        let path = String(data: out.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return path.hasPrefix("/") && fm.isExecutableFile(atPath: path) ? path : nil
    }

    /// Arguments for `claude -p`. Passed as an argv array, never through a shell, so nothing in
    /// the prompt or session context can run as a command.
    static func claudeArgs(system: String, resume: String?) -> [String] {
        // No tools and no MCP servers: a plain chat that can't read or change files, and ~10x less context.
        var args = ["-p", "--output-format", "json", "--max-turns", "2", "--tools", "", "--strict-mcp-config", "--append-system-prompt", system]
        if let resume, isSafeSid(resume) { args += ["--resume", resume] }
        return args
    }

    /// Self-check without network: stream parsing, request shape, status mapping, argv safety.
    static func runChecks() -> String? {
        let (d, _, done) = parseOpenAI(line: #"data: {"choices":[{"delta":{"content":"hi"}}]}"#)
        if d != "hi" || done { return "sse delta" }
        if parseOpenAI(line: #"data: {"choices":[],"usage":{"cost":0.00042}}"#).1 != 0.00042 { return "sse cost" }
        if !parseOpenAI(line: "data: [DONE]").2 { return "sse done" }
        if parseOpenAI(line: ": keep-alive").0 != nil { return "sse comment" }
        if parseAnthropic(line: #"data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"yo"}}"#).0 != "yo" { return "anthropic delta" }
        if !parseAnthropic(line: #"data: {"type":"message_stop"}"#).1 { return "anthropic stop" }
        if parseAnthropic(line: "event: ping").0 != nil { return "anthropic event line" }
        guard let r = request(.anthropic, messages: [ChatMessage(role: "system", content: "s"), ChatMessage(role: "user", content: "u")], key: "k"),
              let b = r.httpBody, let o = try? JSONSerialization.jsonObject(with: b) as? [String: Any],
              o["system"] as? String == "s", (o["messages"] as? [[String: Any]])?.count == 1,
              r.value(forHTTPHeaderField: "x-api-key") == "k", r.value(forHTTPHeaderField: "Authorization") == nil else { return "anthropic request" }
        guard let ro = request(.ollama, messages: [ChatMessage(role: "user", content: "u")], key: ""),
              ro.value(forHTTPHeaderField: "Authorization") == nil, ro.url?.host == "localhost" else { return "ollama request" }
        if case .badKey = map(status: 401) {} else { return "401" }
        if case .noCredits = map(status: 402) {} else { return "402" }
        if case .rateLimited = map(status: 429) {} else { return "429" }
        if redact("bad sk-or-abc here", key: "sk-or-abc").contains("sk-or-abc") { return "redact" }
        let evil = "x\"; rm -rf ~; echo \"$(whoami)`id`"
        let args = claudeArgs(system: evil, resume: "abc; rm -rf ~")
        if args.contains("--resume") || !args.contains(evil) { return "claude argv" }
        if !claudeArgs(system: "s", resume: "18530049-4c61-4e39-a6a4-61c5ea2d2d40").contains("--resume") { return "claude resume" }
        for p in Provider.allCases where p != .claude && p != .ollama && !p.defaultBase.hasPrefix("https://") { return "https \(p)" }
        if Jump.isTTY("/dev/ttys001\" & do shell script \"x") || !Jump.isTTY("/dev/ttys012") { return "tty" }
        if isSafeSid("../x") || isSafeSid("a/b") || !isSafeSid("efaecabf-1234") { return "sid" }
        if !HookInstaller.commandFor("/A/it's/W").contains("'/A/it'\\''s/W'") { return "hook quote" }
        return nil
    }
}
