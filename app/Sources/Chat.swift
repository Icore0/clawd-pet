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

struct ChatLine: Identifiable { let id = UUID(); var role: String; var text: String }

final class ChatModel: ObservableObject {
    @Published var text = ""
    @Published var reply = ""
    @Published var isBusy = false
    @Published var listening = false
    @Published var focusTick = 0
    @Published var placeBelow = false
    @Published var cost: Double = 0
    var status: ChatStatus = .opening
    @Published var lines: [ChatLine] = []
    @Published var provider = Provider.current
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

    func status(for error: ChatError) -> ChatStatus {
        switch error {
        case .noKey, .badKey: return .unauthorized
        case .noCredits: return .outOfCredits
        case .rateLimited: return .rateLimited
        case .offline: return .offline
        case .timeout: return .timeout
        case .server, .other: return .offline
        }
    }

    private func remember(_ answer: String) {
        let a = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        if !a.isEmpty { lines.append(ChatLine(role: "assistant", text: a)) }
        if lines.count > 20 { lines = Array(lines.suffix(20)) }
    }

    func send() {
        let msg = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !msg.isEmpty, !isBusy else { return }
        text = ""; reply = ""; cost = 0; isBusy = true; setListening(false)
        lines.append(ChatLine(role: "user", text: msg))
        if lines.count > 20 { lines = Array(lines.suffix(20)) }
        onChange()
        setStatus(.thinking)
        let p = Provider.current
        if p == .claude { return sendCLI(msg) }
        let messages = [ChatMessage(role: "system", content: Self.persona)] + lines.map { ChatMessage(role: $0.role, content: $0.text) }
        ChatAPI.stream(p, messages: messages, onDelta: { [weak self] chunk in
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
                self.remember(self.reply)
                self.setStatus(.talking)
                self.onReply()
            case .failure(let error):
                self.reply = error.message(p)
                self.setStatus(self.status(for: error))
            }
            self.isBusy = false
            self.onChange()
        })
    }

    static let persona = "You are \(PRODUCT_NAME), a tiny friendly desktop companion who lives on the user's screen next to their Claude Code sessions. Answer briefly (1-4 sentences) unless asked for more. Plain text, no markdown headings."

    /// "Just use Claude": runs the user's own `claude -p`. Arguments go in as an argv array, never through a shell.
    private func sendCLI(_ msg: String) {
        var sys = Self.persona
        let ctx = AppDelegate.shared.model.sessionContext
        if !ctx.isEmpty { sys += "\nThe user is looking at this session: " + ctx }
        let args = ChatAPI.claudeArgs(system: sys, resume: sessionId)
        DispatchQueue.global().async { [weak self] in
            var out = "", ok = false
            if let exe = ChatAPI.claudePath() {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: exe)
                p.arguments = args
                p.currentDirectoryURL = URL(fileURLWithPath: homeDir)
                var env = ProcessInfo.processInfo.environment
                env["WIGGLET_CHAT"] = "1"
                p.environment = env
                let inPipe = Pipe(), outPipe = Pipe()
                p.standardInput = inPipe; p.standardOutput = outPipe; p.standardError = Pipe()
                if (try? p.run()) != nil {
                    ok = true
                    inPipe.fileHandleForWriting.write(Data(msg.utf8)); try? inPipe.fileHandleForWriting.close()
                    DispatchQueue.global().asyncAfter(deadline: .now() + 180) { if p.isRunning { p.terminate() } }
                    out = String(data: outPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
                    p.waitUntilExit()
                }
            }
            var answer = "", sid: String?, failed = false
            if let d = out.data(using: .utf8), let o = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                answer = (o["result"] as? String) ?? ""; sid = o["session_id"] as? String
                failed = (o["is_error"] as? Bool) == true
            }
            if answer.isEmpty {
                failed = true
                answer = ok ? "Claude didn't answer. Run `claude` once in a terminal to log in."
                            : "Couldn't find the claude command. Install Claude Code (claude.com/claude-code), or pick another provider in Settings → Chat."
            }
            DispatchQueue.main.async {
                guard let self else { return }
                if let sid, isSafeSid(sid) { self.sessionId = sid }
                self.reply = answer.trimmingCharacters(in: .whitespacesAndNewlines)
                if failed { self.setStatus(.offline) } else { self.remember(self.reply); self.setStatus(.talking) }
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
    static let width: CGFloat = 420

    var history: [ChatLine] { chat.lines.filter { $0.role != "system" }.suffix(8) }
    var showsLog: Bool { !history.isEmpty || chat.isBusy || !chat.reply.isEmpty }
    var sessionTag: String? {
        let pet = AppDelegate.shared.model
        return pet.sessions.first { $0.sid == pet.chatSid }.map { pet.sessionTag($0) }
    }

    func choose(_ p: Provider) {
        Provider.current = p; chat.provider = p
        chat.newChat()
    }

    /// Provider and model, the session the chat is about, and New.
    var header: some View {
        HStack(spacing: 8) {
            Menu {
                ForEach(Provider.allCases) { p in
                    Button { choose(p) } label: {
                        Text(p.hasKey ? p.label : "\(p.label) (add key in Settings)")
                    }
                }
                Divider()
                Button("Chat settings…") { AppDelegate.shared.showMain(.settings) }
            } label: {
                HStack(spacing: 5) {
                    Rectangle().fill(chat.provider.hasKey ? W.ok : W.clay).frame(width: 6, height: 6)
                    Text(chat.provider == .claude ? "CLAUDE CODE" : "\(chat.provider.label.uppercased()) · \(chat.provider.model)")
                        .font(W.mono(10, .semibold)).tracking(0.4).foregroundStyle(W.ink2).lineLimit(1).truncationMode(.middle)
                    Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)).foregroundStyle(W.ink3)
                }
                .padding(.horizontal, 8).frame(height: 22)
                .overlay(Rectangle().stroke(W.line, lineWidth: 1))
            }
            .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            .help("Who answers. Change it here or in Settings → Chat.")
            if let tag = sessionTag {
                Text("↳ \(tag)").font(W.mono(10, .medium)).foregroundStyle(W.ink3).lineLimit(1).truncationMode(.middle)
                    .help("The chat knows what this session is doing.")
            }
            Spacer(minLength: 4)
            if chat.cost > 0 { Text(String(format: "$%.4f", chat.cost)).font(W.mono(10)).foregroundStyle(W.ink4) }
            if !history.isEmpty {
                Button("NEW") { chat.newChat() }.buttonStyle(.plain).font(W.mono(10, .semibold)).foregroundStyle(W.ink3)
                    .keyboardShortcut("n", modifiers: .command).help("New chat (⌘N)")
            }
        }
        .padding(.horizontal, 12).frame(height: 36)
    }

    func row(_ role: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(role == "user" ? "YOU" : "W").font(W.mono(9.5, .bold))
                .foregroundStyle(role == "user" ? W.ink4 : W.clay).frame(width: 26, alignment: .leading)
            Text(text).font(W.sans(13)).foregroundStyle(role == "user" ? W.ink2 : W.ink)
                .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    var log: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(history) { l in row(l.role, l.text) }
                    if chat.isBusy && chat.reply.isEmpty {
                        HStack(spacing: 5) {
                            Text("W").font(W.mono(9.5, .bold)).foregroundStyle(W.clay).frame(width: 26, alignment: .leading)
                            ForEach(0..<3) { i in
                                TimelineView(.animation) { tl in
                                    Rectangle().fill(W.ink3).frame(width: 5, height: 5)
                                        .offset(y: -3 * max(0, sin(tl.date.timeIntervalSinceReferenceDate * 6 - Double(i) * 0.8)))
                                }
                            }
                        }
                    } else if chat.isBusy || history.last?.role == "user" {
                        // Streaming, or an error that never became part of the history.
                        row("assistant", chat.reply)
                    }
                    Color.clear.frame(height: 1).id("end")
                }
                .padding(.horizontal, 12).padding(.vertical, 12)
            }
            .frame(height: logHeight)
            .onChange(of: chat.reply) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onChange(of: chat.lines.count) { _ in proxy.scrollTo("end", anchor: .bottom) }
            .onAppear { proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    var logHeight: CGFloat {
        let all = history.map(\.text) + [chat.reply]
        let h = all.reduce(CGFloat(0)) { acc, t in
            acc + (t as NSString).boundingRect(with: NSSize(width: Self.width - 70, height: .greatestFiniteMagnitude),
                                               options: .usesLineFragmentOrigin, attributes: [.font: NSFont.systemFont(ofSize: 13)]).height + 10
        }
        return min(280, max(40, ceil(h) + 24))
    }

    var bar: some View {
        HStack(spacing: 10) {
            Text(">").font(W.mono(15, .bold)).foregroundStyle(W.clay)
            TextField("Ask \(PRODUCT_NAME)…", text: $chat.text, axis: .vertical)
                .lineLimit(1...4)
                .textFieldStyle(.plain).font(W.sans(14)).foregroundStyle(W.ink).focused($focused)
                .onSubmit { chat.send() }
                .onChange(of: chat.text) { _ in if chat.listening { chat.setListening(true) } }
            Button { chat.listening ? chat.setListening(false) : chat.startDictation() } label: {
                Image(systemName: chat.listening ? "mic.fill" : "mic")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(chat.listening ? W.clay : W.ink3)
                    .frame(width: 28, height: 28)
                    .overlay(Rectangle().stroke(chat.listening ? W.clay : W.line, lineWidth: 1))
            }.buttonStyle(.plain).help("Dictate").accessibilityLabel(chat.listening ? "Stop dictation" : "Dictate")
            Button { chat.send() } label: {
                Image(systemName: "arrow.up").font(.system(size: 13, weight: .bold))
                    .foregroundStyle(W.bg).frame(width: 28, height: 28)
                    .background(Rectangle().fill(chat.text.isEmpty || chat.isBusy ? W.ink4 : W.clay))
            }.buttonStyle(.plain).disabled(chat.text.isEmpty || chat.isBusy).accessibilityLabel("Send")
        }
        .padding(.horizontal, 12).padding(.vertical, 10)
    }

    var hints: some View {
        HStack(spacing: 12) {
            hint("↩", "send"); hint("⌥↩", "new line"); hint("esc", "close")
            Spacer()
            if chat.isBusy { MonoLabel(text: chat.status == .talking ? "answering" : "thinking", color: W.clay, size: 9.5) }
        }
        .padding(.horizontal, 12).padding(.bottom, 9)
    }
    func hint(_ k: String, _ what: String) -> some View {
        HStack(spacing: 4) {
            Text(k).font(W.mono(9.5, .semibold)).foregroundStyle(W.ink3)
                .padding(.horizontal, 4).frame(height: 15).overlay(Rectangle().stroke(W.soft, lineWidth: 1))
            Text(what.uppercased()).font(W.mono(9.5)).foregroundStyle(W.ink4)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            if showsLog { log; Hairline() }
            bar
            hints
        }
        .frame(width: Self.width)
        .wPanel(W.bg)
        .environment(\.colorScheme, .dark)
        .padding(10).fixedSize()
        .onAppear { focused = true; chat.provider = Provider.current }
        .onChange(of: chat.focusTick) { _ in focused = true; chat.provider = Provider.current }
        .onExitCommand { chat.onClose() }
    }
}
