import SwiftUI

let kindIcon: [Kind: String] = [.read: "doc.text", .edit: "pencil", .bash: "terminal", .search: "magnifyingglass", .web: "globe",
    .agent: "person.2", .plan: "checklist", .compact: "arrow.down.right.and.arrow.up.left", .test: "testtube.2", .build: "hammer",
    .git: "arrow.triangle.branch", .install: "shippingbox", .ask: "hand.raised", .think: "ellipsis"]

/// Glass card shown on hover. Clickable: it stays open while the pointer moves onto it, shows the session's latest
/// assistant message live (read locally, display only) and can jump to the session's window.
struct ActivityView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var watcher: TranscriptWatcher
    var onJump: (SessionPet) -> Void = { _ in }
    var onClose: () -> Void = {}

    func ago(_ ts: Double) -> String {
        let s = Int(Date().timeIntervalSince1970 - ts / 1000)
        return s < 5 ? "now" : s < 60 ? "\(s)s" : "\(s / 60)m"
    }
    func clock(_ d: Date) -> String { let s = Int(Date().timeIntervalSince(d)); return String(format: "%d:%02d", s / 60, s % 60) }
    func status(_ mood: String) -> String {
        switch mood {
        case "waiting": return "needs you"
        case "working": return "working"
        case "stalled": return "quiet 15m"
        case "done": return "done"
        default: return "idle"
        }
    }

    /// Offscreen README renders: no timeline, and a solid panel where the live card uses glass.
    static var offscreen = false

    var body: some View {
        Group {
            if ActivityView.offscreen { panel } else { TimelineView(.periodic(from: .now, by: 1)) { _ in panel } }
        }
        .padding(10).fixedSize()
        .onHover { model.cardHover = $0 }
        .background(
            // Esc closes the card from the keyboard.
            Button("", action: onClose).keyboardShortcut(.cancelAction).opacity(0).accessibilityHidden(true)
        )
    }

    @ViewBuilder var panel: some View {
        let shown = model.sessions.first { $0.sid == model.cardSid }
        let content = VStack(alignment: .leading, spacing: 9) {
                if model.badgeHover {
                    let hidden = Array(model.displaySessions.dropFirst(6))
                    Text("+\(hidden.count)").font(.system(size: 13, weight: .semibold))
                    ForEach(hidden) { s in
                        Text(s.say.isEmpty ? model.sessionTag(s) : "\(model.sessionTag(s))  \(s.say)")
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    }
                } else if model.oneWigglet && model.sessions.count > 1 {
                    everyone
                } else if let s = shown {
                    card(s)
                } else {
                    Text("Nothing yet. Ask Claude Code something and watch me work.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(16).frame(width: 330)
            .environment(\.colorScheme, .dark)
        if ActivityView.offscreen {
            content.wPanel()
        } else {
            content.wPanel()
        }
    }

    /// One-Wigglet mode: every session in one list, each with its own Jump.
    @ViewBuilder var everyone: some View {
        MonoLabel(text: "\(model.sessions.count) sessions", color: W.clay, size: 10)
        ForEach(model.sortedSessions) { s in
            let waiting = s.mood == "waiting", working = s.mood == "working"
            HStack(spacing: 8) {
                Rectangle().fill(waiting ? W.clay : working ? W.ok : W.ink4).frame(width: 8, height: 8).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.sessionTag(s)).font(W.sans(13, .medium)).foregroundStyle(W.ink).lineLimit(1).truncationMode(.middle)
                    Text(s.say.isEmpty ? "\(status(s.mood)) · \(ago(s.ts))" : s.say).font(.system(size: 11)).foregroundStyle(W.ink3).lineLimit(1)
                }
                .help(s.cwd)
                Spacer(minLength: 6)
                if !ActivityView.offscreen {
                    Button("Jump ↗") { onJump(s) }.buttonStyle(WButton(kind: .line, small: true))
                        .accessibilityLabel("Jump to \(model.sessionTag(s)) session")
                }
            }
            .accessibilityElement(children: .contain)
        }
    }

    @ViewBuilder func card(_ s: SessionPet) -> some View {
        let waiting = s.mood == "waiting", working = s.mood == "working"
        HStack(spacing: 8) {
            Rectangle().fill(waiting ? W.clay : working ? W.ok : W.ink4).frame(width: 8, height: 8)
                .accessibilityHidden(true)
            Text(model.sessionTag(s)).font(W.sans(14, .medium)).foregroundStyle(W.ink).lineLimit(1).truncationMode(.middle)
                .help(s.cwd)
            MonoLabel(text: status(s.mood), color: waiting ? W.clay : W.ink3, size: 10)
            Spacer()
            if ActivityView.offscreen {
                Text("JUMP ↗").font(W.mono(10.5, .semibold)).foregroundStyle(W.ink).padding(.horizontal, 9).frame(height: 24).overlay(Rectangle().stroke(W.line, lineWidth: 1))
            } else {
                Button("Jump ↗") { onJump(s) }
                .buttonStyle(WButton(kind: .line, small: true))
                .keyboardShortcut(.defaultAction)
                .help("Jump to this session (Return or ⌘J)")
                .accessibilityLabel("Jump to \(model.sessionTag(s)) session")
                Button("") { onJump(s) }.keyboardShortcut("j", modifiers: .command).opacity(0).frame(width: 0).accessibilityHidden(true)
            }
        }
        .accessibilityElement(children: .contain)
        if !s.say.isEmpty {
            Text(s.delta.isEmpty ? s.say : "\(s.say) \(s.delta)").font(.system(size: 12)).lineLimit(1)
        }
        HStack(spacing: 14) {
            if let ms = s.turnStart { Label(clock(Date(timeIntervalSince1970: ms / 1000)), systemImage: "timer") }
            Label(s.toolCount == 1 ? "1 tool" : "\(s.toolCount) tools", systemImage: "wrench.and.screwdriver")
        }.font(.system(size: 11)).foregroundStyle(.secondary)
        if model.showLatest && !watcher.latest.message.isEmpty {
            latest(watcher.latest)
        }
        Divider().opacity(0.4)
        if s.events.isEmpty {
            Text("Nothing yet. Ask Claude Code something and watch me work.").font(.system(size: 12)).foregroundStyle(.secondary)
        } else {
            ForEach(Array(s.events.suffix(6).reversed())) { e in
                HStack(spacing: 8) {
                    Image(systemName: kindIcon[e.kind] ?? "circle.fill").font(.system(size: 11)).frame(width: 16).foregroundStyle(W.clay)
                        .accessibilityHidden(true)
                    Text(e.text.isEmpty ? e.kind.rawValue : e.text).font(.system(size: 12)).lineLimit(1)
                    Spacer(minLength: 6)
                    Text(ago(e.ts)).font(.system(size: 10)).foregroundStyle(.tertiary)
                }
            }
        }
    }

    @ViewBuilder func latest(_ l: TranscriptReader.Latest) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            MonoLabel(text: "Latest message", color: W.clay, size: 10)
            if !l.prompt.isEmpty {
                Text("› " + l.prompt).font(.system(size: 11)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.tail)
            }
            let long = l.message.count > 280
            let expanded = model.cardExpanded
            if expanded && long {
                ScrollView { Text(l.message).font(.system(size: 12)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading) }
                    .frame(maxHeight: 220)
            } else {
                Text(long ? String(l.message.prefix(280)) + "…" : l.message).font(.system(size: 12)).lineLimit(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if long {
                Button(expanded ? "less" : "more") { model.cardExpanded.toggle(); model.objectWillChange.send() }
                    .buttonStyle(.borderless).font(.system(size: 11, weight: .medium))
                    .accessibilityLabel(expanded ? "Show less of the latest message" : "Show the whole latest message")
            }
        }
        .padding(10)
        .background(Rectangle().fill(W.raised))
        .overlay(Rectangle().stroke(W.soft, lineWidth: 1))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Latest message: \(l.message)")
    }
}

/// One-line notice after a jump that couldn't target the exact tab.
struct ToastView: View {
    @ObservedObject var model: PetModel
    var body: some View {
        Text(model.toast)
            .font(.system(size: 12, weight: .medium))
            .padding(.horizontal, 14).padding(.vertical, 8)
            .foregroundStyle(W.ink)
            .wPanel()
            .padding(6).fixedSize()
            .accessibilityLabel(model.toast)
    }
}
