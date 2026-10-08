import Foundation

/// Reads the newest assistant message and the user's last prompt from a Claude Code transcript (JSONL),
/// for display in the hover card only. Nothing read here is stored, logged or sent anywhere.
enum TranscriptReader {
    static let tailBytes = 65_536

    struct Latest: Equatable {
        var message = ""
        var prompt = ""
    }

    /// Reads at most the last 64 KB and parses lines from the end. A partial first line is skipped.
    static func read(path: String) -> Latest {
        guard let fh = FileHandle(forReadingAtPath: path) else { return Latest() }
        defer { try? fh.close() }
        let size = (try? fh.seekToEnd()) ?? 0
        let start = size > UInt64(tailBytes) ? size - UInt64(tailBytes) : 0
        try? fh.seek(toOffset: start)
        guard let data = try? fh.readToEnd(), !data.isEmpty else { return Latest() }
        var lines = data.split(separator: UInt8(ascii: "\n"), omittingEmptySubsequences: true)
        if start > 0, !lines.isEmpty { lines.removeFirst() }
        return parse(lines: lines.reversed().map { Data($0) })
    }

    /// `lines` newest first.
    static func parse(lines: [Data]) -> Latest {
        var out = Latest()
        for line in lines {
            if !out.message.isEmpty && !out.prompt.isEmpty { break }
            guard let o = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else { continue }
            if (o["isSidechain"] as? Bool) == true || (o["isMeta"] as? Bool) == true { continue }
            let type = o["type"] as? String ?? ""
            if type == "last-prompt", out.prompt.isEmpty, let p = o["lastPrompt"] as? String {
                out.prompt = clean(p)
                continue
            }
            guard let msg = o["message"] as? [String: Any] else { continue }
            if type == "assistant", out.message.isEmpty, let blocks = msg["content"] as? [[String: Any]] {
                let text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined(separator: "\n")
                if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { out.message = clean(text) }
            } else if type == "user", out.prompt.isEmpty {
                var text = ""
                if let s = msg["content"] as? String { text = s }
                else if let blocks = msg["content"] as? [[String: Any]] {
                    text = blocks.filter { ($0["type"] as? String) == "text" }.compactMap { $0["text"] as? String }.joined(separator: " ")
                }
                if !text.isEmpty && !text.hasPrefix("<") { out.prompt = clean(text) }
            }
        }
        return out
    }

    /// Strips basic markdown so the card reads as plain text.
    static func clean(_ s: String) -> String {
        var out: [String] = []
        for raw in s.split(separator: "\n", omittingEmptySubsequences: false) {
            var line = String(raw)
            if line.hasPrefix("```") { continue }
            while line.hasPrefix("#") { line.removeFirst() }
            if line.hasPrefix("- ") || line.hasPrefix("* ") { line = "• " + line.dropFirst(2) }
            line = line.replacingOccurrences(of: "**", with: "").replacingOccurrences(of: "`", with: "")
            out.append(line.trimmingCharacters(in: .whitespaces))
        }
        return out.joined(separator: "\n").replacingOccurrences(of: "\n\n\n", with: "\n\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func selfCheck() -> String? {
        let lines = [
            #"{"type":"last-prompt","lastPrompt":"fix the **build**"}"#,
            ###"{"type":"assistant","isSidechain":false,"message":{"role":"assistant","content":[{"type":"text","text":"## Done\n- tests **pass**"},{"type":"tool_use","name":"Bash"}]}}"###,
            #"{"type":"assistant","isSidechain":true,"message":{"role":"assistant","content":[{"type":"text","text":"sub-agent chatter"}]}}"#,
            #"{"type":"user","isMeta":true,"message":{"role":"user","content":"<system>"}}"#,
        ].map { Data($0.utf8) }    // newest first, as parse() expects
        let got = parse(lines: lines)
        if got.message != "Done\n• tests pass" { return "transcript message: \(got.message)" }
        if got.prompt != "fix the build" { return "transcript prompt: \(got.prompt)" }
        return nil
    }
}

/// Watches one transcript file and republishes the latest message, at most 4 times a second, off the main thread.
final class TranscriptWatcher: ObservableObject {
    @Published private(set) var latest = TranscriptReader.Latest()
    private(set) var path = ""
    private var source: DispatchSourceFileSystemObject?
    private let queue = DispatchQueue(label: "clawd.transcript", qos: .utility)
    private var lastRead = Date.distantPast
    private var pending = false

    func watch(_ newPath: String) {
        guard newPath != path else { return }
        stop()
        path = newPath
        latest = TranscriptReader.Latest()
        guard !newPath.isEmpty else { return }
        open()
        refresh()
    }

    /// Shows a fixed message without a file (offscreen README renders).
    func preview(_ l: TranscriptReader.Latest) { latest = l }

    func stop() {
        source?.cancel()
        source = nil
        path = ""
    }

    private func open() {
        let fd = Darwin.open(path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend, .delete, .rename], queue: queue)
        src.setEventHandler { [weak self, weak src] in
            guard let self, let src else { return }
            if src.data.contains(.delete) || src.data.contains(.rename) {
                // The file was replaced: watch the new one at the same path.
                src.cancel()
                self.queue.asyncAfter(deadline: .now() + 0.2) { [weak self] in self?.reopen() }
            }
            self.refresh()
        }
        src.setCancelHandler { Darwin.close(fd) }
        src.resume()
        source = src
    }

    private func reopen() {
        guard !path.isEmpty else { return }
        open()
        refresh()
    }

    /// Throttled read on the background queue.
    private func refresh() {
        let path = self.path
        queue.async { [weak self] in
            guard let self else { return }
            let wait = 0.25 - Date().timeIntervalSince(self.lastRead)
            if wait > 0 {
                if self.pending { return }
                self.pending = true
                self.queue.asyncAfter(deadline: .now() + wait) { [weak self] in self?.pending = false; self?.refresh() }
                return
            }
            self.lastRead = Date()
            let next = TranscriptReader.read(path: path)
            DispatchQueue.main.async {
                if self.path == path && next != self.latest { self.latest = next }
            }
        }
    }
}
