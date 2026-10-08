import AppKit
import SwiftUI

extension View {
    /// Liquid Glass on macOS 26+, frosted material before that.
    @ViewBuilder func glass<S: Shape>(_ shape: S, tint: Color? = nil) -> some View {
        if #available(macOS 26.0, *) {
            if let tint { self.glassEffect(.regular.tint(tint), in: shape) } else { self.glassEffect(.regular, in: shape) }
        } else {
            self.background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(Color.white.opacity(0.28), lineWidth: 0.7))
                .shadow(color: .black.opacity(0.2), radius: 10, y: 4)
        }
    }
}

enum ChatStatus: String {
    case opening, listening, reading, thinking, talking, offline, outOfCredits, rateLimited, unauthorized, timeout
}

struct ChatLine { var role: String; var text: String }

final class ChatModel: ObservableObject {
    @Published var text = ""
    @Published var reply = ""
    @Published var isBusy = false
    @Published var listening = false
    @Published var focusTick = 0
    @Published var placeBelow = false
    @Published var keyNote = ""
    @Published var cost: Double = 0
    var status: ChatStatus = .opening
    var lines: [ChatLine] = []
    var model = orModels[0].id
    var useCLI = UserDefaults.standard.bool(forKey: "useClaudeCLI")
    var sessionId: String?
    var onChange: () -> Void = {}
    var onReply: () -> Void = {}
    var onClose: () -> Void = {}
    var onListening: (Bool) -> Void = { _ in }
    var onStatus: (ChatStatus) -> Void = { _ in }
    private var listenTimer: Timer?

    func setStatus(_ next: ChatStatus) {
        status = next
        onStatus(next)
    }

    func sessionSummary() -> String {
        let pet = AppDelegate.shared.model
        let session = pet.sessions.first { $0.sid == pet.chatSid } ?? pet.sessions.first
        guard let session else { return "no session" }
        var parts = [
            "project: \(session.project)",
            "cwd: \(session.cwd)",
            "activity: \(session.activityId.isEmpty ? session.kind.rawValue : session.activityId)"
        ]
        let events = session.events.suffix(20).map(\.text).filter { !$0.isEmpty }
        if !events.isEmpty { parts.append(events.joined(separator: "\n")) }
        let turn = session.turnStart.map { String($0) } ?? "none"
        parts.append("turnStart: \(turn) toolCount: \(session.toolCount) lastDurationMs: \(session.lastDurationMs) errorStreak: \(session.errorStreak)")
        if UserDefaults.standard.bool(forKey: "transcriptTail"), !session.transcript.isEmpty, let path = Optional(session.transcript),
           let data = FileManager.default.contents(atPath: path),
           let raw = String(data: data, encoding: .utf8) {
            let tail = raw.split(separator: "\n").suffix(20).joined(separator: "\n")
            if !tail.isEmpty { parts.append(tail) }
        }
        return parts.joined(separator: "\n")
    }

    /// One system message for the character whose chat just opened. Transcript text stays out unless `transcriptTail` is true.
    func attachSession() {
        lines.removeAll { $0.role == "system" }
        lines.insert(ChatLine(role: "system", text: sessionSummary()), at: 0)
        if lines.count > 20 { lines = Array(lines.suffix(20)) }
        onChange()
    }

    func status(for error: ORError) -> ChatStatus {
        switch error {
        case .noKey, .badKey: return .unauthorized
        case .noCredits: return .outOfCredits
        case .rateLimited: return .rateLimited
        case .offline: return .offline
        case .timeout: return .timeout
        case .server, .other: return .offline
        }
    }

    func send() {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\n", with: " ")
        guard !msg.isEmpty, !isBusy else { return }
        text = ""; reply = ""; cost = 0; isBusy = true; setListening(false); onChange()
        lines.append(ChatLine(role: "user", text: msg))
        if lines.count > 20 { lines = Array(lines.suffix(20)) }
        setStatus(.reading)
        if !useCLI, let key = KeychainStore.load(), !key.isEmpty {
            setStatus(.thinking)
            let messages = lines.suffix(20).map { ORMessage(role: $0.role, content: $0.text) }
            OpenRouter.stream(messages: messages, model: model, key: key, onDelta: { [weak self] chunk in
                guard let self else { return }
                if self.status != .talking { self.setStatus(.talking) }
                self.reply += chunk
                self.onChange()
            }, onCost: { [weak self] value in
                self?.cost = value
                self?.onChange()
            }, onDone: { [weak self] result in
                guard let self else { return }
                switch result {
                case .success:
                    let answer = self.reply.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !answer.isEmpty {
                        self.lines.append(ChatLine(role: "assistant", text: answer.replacingOccurrences(of: "\n", with: " ")))
                        if self.lines.count > 20 { self.lines = Array(self.lines.suffix(20)) }
                    }
                    self.setStatus(.talking)
                    self.onReply()
                case .failure(let error):
                    self.reply = error.message
                    self.setStatus(self.status(for: error))
                }
                self.isBusy = false
                self.onChange()
            })
            return
        }
        setStatus(.thinking)
        let resume = sessionId.map { " --resume \($0)" } ?? ""
        var sys = "You are \(PRODUCT_NAME), a tiny friendly desktop companion who lives on the user's screen. Answer briefly (1-4 sentences) unless asked for more. Plain text, no markdown headings."
        let ctx = AppDelegate.shared.model.sessionContext
        if !ctx.isEmpty {
            let safe = ctx.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")
                .replacingOccurrences(of: "`", with: "\\`")
            sys += "\n" + safe
        }
        let cmd = "claude -p --output-format json --max-turns 8 --append-system-prompt \"\(sys)\"\(resume)"
        DispatchQueue.global().async { [weak self] in
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/bin/zsh")
            p.arguments = ["-lc", cmd]
            p.currentDirectoryURL = FileManager.default.homeDirectoryForCurrentUser
            let inPipe = Pipe(), outPipe = Pipe()
            p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = Pipe()
            var out = "", ok = true
            do {
                try p.run()
                inPipe.fileHandleForWriting.write(Data(msg.utf8)); try? inPipe.fileHandleForWriting.close()
                DispatchQueue.global().asyncAfter(deadline: .now() + 180) { if p.isRunning { p.terminate() } }
                out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                p.waitUntilExit()
            } catch { ok = false }
            var answer = "", sid: String?
            if let d = out.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                answer = (o["result"] as? String) ?? ""; sid = o["session_id"] as? String
            }
            if answer.isEmpty {
                answer = ok && !out.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !out.hasPrefix("{")
                    ? out : "I couldn't reach Claude Code. Is `claude` installed and logged in? (npm i -g @anthropic-ai/claude-code, then run `claude` once.)"
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let sid { self.sessionId = sid }
                self.reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if !self.reply.isEmpty {
                    self.lines.append(ChatLine(role: "assistant", text: self.reply.replacingOccurrences(of: "\n", with: " ")))
                    if self.lines.count > 20 { self.lines = Array(self.lines.suffix(20)) }
                }
                self.setStatus(.talking)
                self.isBusy = false; self.onChange(); self.onReply()
            }
        }
    }

    func newChat() { sessionId = nil; reply = ""; lines = []; onChange() }

    func startDictation() {
        focusTick += 1
        setListening(true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            NSApp.sendAction(Selector(("startDictation:")), to: nil, from: nil)
        }
    }
    func setListening(_ on: Bool) {
        listening = on; onListening(on)
        if on { setStatus(.listening) }
        listenTimer?.invalidate()
        if on { listenTimer = Timer.scheduledTimer(withTimeInterval: 25, repeats: false) { [weak self] _ in self?.setListening(false) } }
    }
}

struct ChatView: View {
    @ObservedObject var chat: ChatModel
    @FocusState private var focused: Bool
    static let width: CGFloat = 400

    var replyHeight: CGFloat {
        let h = (chat.reply as NSString).boundingRect(with: NSSize(width: Self.width - 56, height: .greatestFiniteMagnitude),
                                                      options: .usesLineFragmentOrigin, attributes: [.font: NSFont.systemFont(ofSize: 13)]).height
        return min(240, max(22, ceil(h) + 4))
    }

    var bar: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkle").font(.system(size: 14, weight: .semibold)).foregroundStyle(wiggletOrange)
            TextField("Ask \(PRODUCT_NAME)…", text: $chat.text)
                .textFieldStyle(.plain).font(.system(size: 14)).focused($focused)
                .onSubmit { chat.send() }
                .onChange(of: chat.text) { _ in if chat.listening { chat.setListening(true) } }
            Button { chat.listening ? chat.setListening(false) : chat.startDictation() } label: {
                Image(systemName: chat.listening ? "mic.fill" : "mic")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(chat.listening ? Color.red : Color.primary.opacity(0.75))
                    .frame(width: 26, height: 26)
                    .background(Rectangle().fill(chat.listening ? W.clay.opacity(0.22) : Color.clear))
            }.buttonStyle(.plain).help("Dictate (uses macOS Dictation or your dictation app)")
            Button { chat.send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.bg).frame(width: 28, height: 28)
                    .background(Rectangle().fill(chat.text.isEmpty || chat.isBusy ? W.ink4 : W.clay))
            }.buttonStyle(.plain).disabled(chat.text.isEmpty || chat.isBusy)
        }
        .padding(.horizontal, 16).frame(width: Self.width, height: 48)
        .wPanel()
        .environment(\.colorScheme, .dark)
    }

    var card: some View {
        VStack(alignment: .leading, spacing: 6) {
            if chat.isBusy && chat.reply.isEmpty {
                HStack(spacing: 5) {
                    ForEach(0..<3) { i in
                        TimelineView(.animation) { tl in
                            Rectangle().fill(W.ink2).frame(width: 6, height: 6)
                                .offset(y: -3 * max(0, sin(tl.date.timeIntervalSinceReferenceDate * 6 - Double(i) * 0.8)))
                        }
                    }
                }.padding(.vertical, 6)
            } else {
                ScrollView { Text(chat.reply).font(.system(size: 13)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(height: replyHeight)
            }
            HStack {
                if chat.cost > 0 {
                    Text(String(format: "$%.4f", chat.cost)).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                Spacer()
                Button("New chat") { chat.newChat() }.buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
                Button("Copy") { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(chat.reply, forType: .string) }
                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 10).frame(width: Self.width)
        .wPanel()
        .environment(\.colorScheme, .dark)
    }

    var body: some View {
        VStack(spacing: 8) {
            if !chat.keyNote.isEmpty {
                Text(chat.keyNote).font(.system(size: 11)).foregroundStyle(.secondary).frame(width: Self.width, alignment: .leading)
            }
            if chat.placeBelow {
                bar; if chat.isBusy || !chat.reply.isEmpty { card }
            } else {
                if chat.isBusy || !chat.reply.isEmpty { card }; bar
            }
        }
        .padding(10).fixedSize()
        .onAppear { focused = true }
        .onChange(of: chat.focusTick) { _ in focused = true }
        .onExitCommand { chat.onClose() }
    }
}
