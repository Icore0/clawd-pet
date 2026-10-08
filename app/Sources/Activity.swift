import SwiftUI

let kindIcon: [Kind: String] = [.read: "doc.text", .edit: "pencil", .bash: "terminal", .search: "magnifyingglass", .web: "globe",
    .agent: "person.2", .plan: "checklist", .compact: "arrow.down.right.and.arrow.up.left", .test: "testtube.2", .build: "hammer",
    .git: "arrow.triangle.branch", .install: "shippingbox", .ask: "hand.raised", .think: "ellipsis"]

/// Glass card shown on hover: what Claude Code is doing right now, plus the last few actions.
struct ActivityView: View {
    @ObservedObject var model: PetModel

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
        default: return "idle"
        }
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { _ in
            let hovered = model.sessions.first { $0.sid == model.hoveredSid }
            VStack(alignment: .leading, spacing: 9) {
                if model.badgeHover {
                    let hidden = Array(model.displaySessions.dropFirst(6))
                    Text("+\(hidden.count)").font(.system(size: 13, weight: .semibold))
                    ForEach(hidden) { s in
                        Text(s.say.isEmpty ? model.sessionTag(s) : "\(model.sessionTag(s))  \(s.say)")
                            .font(.system(size: 12)).lineLimit(1).truncationMode(.middle)
                    }
                } else if let s = hovered {
                    let waiting = s.mood == "waiting", working = s.mood == "working"
                    HStack(spacing: 8) {
                        Circle().fill(waiting ? Color.orange : working ? Color.green : Color.gray).frame(width: 8, height: 8)
                        Text(model.sessionTag(s)).font(.system(size: 13, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Text(status(s.mood)).font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                    }
                    if !s.say.isEmpty {
                        Text(s.delta.isEmpty ? s.say : "\(s.say) \(s.delta)").font(.system(size: 12)).lineLimit(1)
                    }
                    HStack(spacing: 14) {
                        if let ms = s.turnStart {
                            Label(clock(Date(timeIntervalSince1970: ms / 1000)), systemImage: "timer")
                        }
                        Label("\(s.toolCount) tools", systemImage: "wrench.and.screwdriver")
                    }.font(.system(size: 11)).foregroundStyle(.secondary)
                    Divider().opacity(0.4)
                    if s.events.isEmpty {
                        Text("Nothing yet. Ask Claude Code something and watch me work.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        ForEach(Array(s.events.suffix(6).reversed())) { e in
                            HStack(spacing: 8) {
                                Image(systemName: kindIcon[e.kind] ?? "circle.fill").font(.system(size: 11)).frame(width: 16).foregroundStyle(clawdOrange)
                                Text(e.text.isEmpty ? e.kind.rawValue : e.text).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 6)
                                Text(ago(e.ts)).font(.system(size: 10)).foregroundStyle(.tertiary)
                            }
                        }
                    }
                } else {
                    Text("Nothing yet. Ask Claude Code something and watch me work.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
            }
            .padding(14).frame(width: 300)
            .glass(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .padding(10).fixedSize()
    }
}
