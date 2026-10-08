import Foundation
import Security

// OpenRouter chat backend. Written and reviewed by Claude; UI wiring is separate.
// Rules: the API key lives only in the Keychain, never in UserDefaults/files/logs, and is redacted from every error string.

enum KeychainStore {
    static var service: String { Bundle.main.bundleIdentifier ?? "dev.wigglet.app" }
    static let account = "openrouter"

    static func save(_ key: String) -> Bool {
        let data = Data(key.utf8)
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        SecItemDelete(q as CFDictionary)
        var add = q
        add[kSecValueData as String] = data
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
    static func load() -> String? {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account,
                                kSecReturnData as String: true, kSecMatchLimit as String: kSecMatchLimitOne]
        var out: AnyObject?
        guard SecItemCopyMatching(q as CFDictionary, &out) == errSecSuccess, let d = out as? Data else { return nil }
        let s = String(data: d, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return (s?.isEmpty ?? true) ? nil : s
    }
    @discardableResult static func delete() -> Bool {
        let q: [String: Any] = [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: account]
        let r = SecItemDelete(q as CFDictionary)
        return r == errSecSuccess || r == errSecItemNotFound
    }
}

struct ORMessage: Codable { var role: String; var content: String }   // role: system | user | assistant

enum ORError: Error {
    case noKey, badKey, noCredits, rateLimited, offline, timeout, server(Int), other
    var message: String {
        switch self {
        case .noKey: return "Add your OpenRouter key in AI settings."
        case .badKey: return "OpenRouter rejected the key. Check it in AI settings."
        case .noCredits: return "Out of OpenRouter credits."
        case .rateLimited: return "Rate limited. Try again in a moment."
        case .offline: return "No connection."
        case .timeout: return "That took too long. Try again."
        case .server(let c): return "OpenRouter error (\(c))."
        case .other: return "Something went wrong."
        }
    }
}

struct ORModelChoice { let id: String; let label: String }
/// Editable list: adding a model is one line. First entry is the default (cheap and fast).
let orModels: [ORModelChoice] = [
    ORModelChoice(id: "anthropic/claude-haiku-4.5", label: "Claude Haiku 4.5"),
    ORModelChoice(id: "google/gemini-2.5-flash", label: "Gemini 2.5 Flash"),
    ORModelChoice(id: "openai/gpt-4o-mini", label: "GPT-4o mini"),
]

enum OpenRouter {
    static let defaultBase = "https://openrouter.ai/api/v1"

    /// The base URL can only be overridden when HOME is a temp dir (tests with a mock server), so a real key can never be redirected.
    static var base: String {
        let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
        if (home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/")), let o = ProcessInfo.processInfo.environment["OPENROUTER_BASE_URL"], !o.isEmpty { return o }
        return defaultBase
    }

    static func redact(_ s: String, key: String) -> String {
        key.isEmpty ? s : s.replacingOccurrences(of: key, with: "[key]")
    }

    static func map(status: Int) -> ORError {
        switch status {
        case 401, 403: return .badKey
        case 402: return .noCredits
        case 429: return .rateLimited
        default: return .server(status)
        }
    }
    static func map(error: Error) -> ORError {
        if let e = error as? ORError { return e }
        let c = (error as NSError)
        if c.domain == NSURLErrorDomain {
            switch c.code {
            case NSURLErrorTimedOut: return .timeout
            case NSURLErrorNotConnectedToInternet, NSURLErrorNetworkConnectionLost, NSURLErrorCannotFindHost, NSURLErrorCannotConnectToHost, NSURLErrorDNSLookupFailed: return .offline
            case NSURLErrorCancelled: return .other
            default: return .other
            }
        }
        return .other
    }

    /// Parses one SSE line. Returns (delta, costUSD, done).
    static func parse(line: String) -> (String?, Double?, Bool) {
        guard line.hasPrefix("data:") else { return (nil, nil, false) }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { return (nil, nil, true) }
        guard let d = payload.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] else { return (nil, nil, false) }
        var delta: String?
        if let ch = (o["choices"] as? [[String: Any]])?.first, let dl = ch["delta"] as? [String: Any], let t = dl["content"] as? String, !t.isEmpty { delta = t }
        var cost: Double?
        if let u = o["usage"] as? [String: Any] { cost = (u["cost"] as? NSNumber)?.doubleValue }
        return (delta, cost, false)
    }

    /// Streams a reply. Callbacks run on the main thread. Returns a Task you can cancel.
    @discardableResult
    static func stream(messages: [ORMessage], model: String, key: String,
                       onDelta: @escaping (String) -> Void, onCost: @escaping (Double) -> Void,
                       onDone: @escaping (Result<Void, ORError>) -> Void) -> Task<Void, Never> {
        Task {
            func finish(_ r: Result<Void, ORError>) { DispatchQueue.main.async { onDone(r) } }
            guard !key.isEmpty else { return finish(.failure(.noKey)) }
            guard let url = URL(string: base + "/chat/completions") else { return finish(.failure(.other)) }
            var req = URLRequest(url: url, timeoutInterval: 60)
            req.httpMethod = "POST"
            req.setValue("Bearer " + key, forHTTPHeaderField: "Authorization")
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.setValue("https://github.com/wigglet", forHTTPHeaderField: "HTTP-Referer")
            req.setValue("Wigglet", forHTTPHeaderField: "X-Title")
            let body: [String: Any] = ["model": model, "stream": true, "usage": ["include": true],
                                       "messages": messages.suffix(20).map { ["role": $0.role, "content": $0.content] }]
            req.httpBody = try? JSONSerialization.data(withJSONObject: body)
            do {
                let (bytes, resp) = try await URLSession.shared.bytes(for: req)
                if let h = resp as? HTTPURLResponse, h.statusCode != 200 { return finish(.failure(map(status: h.statusCode))) }
                var got = false
                for try await line in bytes.lines {
                    if Task.isCancelled { return finish(.failure(.other)) }
                    let (delta, cost, done) = parse(line: line)
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

    /// Self-check without network: SSE parsing and status mapping.
    static func runChecks() -> String? {
        let (d, _, done) = parse(line: #"data: {"choices":[{"delta":{"content":"hi"}}]}"#)
        if d != "hi" || done { return "sse delta" }
        let (_, c, _) = parse(line: #"data: {"choices":[],"usage":{"cost":0.00042}}"#)
        if c != 0.00042 { return "sse cost" }
        if !parse(line: "data: [DONE]").2 { return "sse done" }
        if parse(line: ": keep-alive").0 != nil { return "sse comment" }
        if case .badKey = map(status: 401) {} else { return "401" }
        if case .noCredits = map(status: 402) {} else { return "402" }
        if case .rateLimited = map(status: 429) {} else { return "429" }
        if redact("bad sk-or-abc here", key: "sk-or-abc").contains("sk-or-abc") { return "redact" }
        return nil
    }
}
