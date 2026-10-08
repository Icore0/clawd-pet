import AppKit
import SwiftUI

let homeDir = ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory()
let stateRoot = homeDir + "/.claude/" + PRODUCT_SLUG
let sessionsDir = stateRoot + "/sessions"

enum Kind: String { case think, read, edit, bash, search, web, agent, plan, compact, test, build, git, install, ask, yourTurn, hello, bye, none }

struct Ev: Identifiable { let ts: Double; let kind: Kind; let text: String; var id: Double { ts } }

struct SessionPet: Identifiable {
    var sid: String
    var cwd: String
    var project: String
    var startedAt: Double
    var transcript: String
    var lastTool: String
    var toolCount: Int
    var turnStart: Double?
    var errorStreak: Int
    var lastErrorAt: Double?
    var mood: String
    var kind: Kind
    var say: String
    var delta: String
    var ts: Double
    var activityId: String = ""
    var subagentCount: Int = 0
    var lastDurationMs: Double = 0
    var toolStartedAt: Double?
    var toolTimes: [Double] = []
    /// Where the session runs (recorded by the hook at SessionStart), for "Jump to session".
    var hostBundleId = ""
    var hostPid: Int32 = 0
    var hostApp = ""
    var tty = ""
    /// Last time this session was working, waiting, hello, bye, done, or oops. A newer file `ts` moves it to now.
    var lastNonIdle: Date = .distantPast
    var events: [Ev] = []
    var id: String { sid }
}

func teamStride(_ scale: Double) -> Double { 13 * scale + 8 }
func teamPanelWidth(count: Int, scale: Double) -> Double {
    let slots = Double(min(6, max(1, count)))
    let extra: Double = count > 6 ? 44 : 0
    return 16 + slots * teamStride(scale) + extra
}

/// Everything the sprite needs to know. Mutated from the main thread only.
final class PetModel: ObservableObject {
    let labels = TextCache()
    // from Claude Code hooks (aggregated over all sessions)
    var mood = "idle"            // idle working waiting done oops hello bye
    var kind = Kind.none
    var say = ""           // detail line: file name, pattern, description…
    var delta = ""         // +12 −3
    var stamp = 0.0         // ts of the current event (seeds the quip)
    var project = ""
    var sessions: [SessionPet] = []
    var hoveredSid: String?
    /// The session the hover card shows. Survives the pointer moving from the Clawd onto the card.
    var cardSid: String?
    var cardHover = false
    var cardExpanded = false
    var toast = ""
    var showLatest: Bool {
        get { UserDefaults.standard.object(forKey: "cardLatest") == nil ? true : UserDefaults.standard.bool(forKey: "cardLatest") }
        set { UserDefaults.standard.set(newValue, forKey: "cardLatest") }
    }
    var badgeHover = false
    var selectedSid: String?
    var sessionContext = ""
    var lastMood: [String: String] = [:]
    var soundNow: [String] = []
    private var moodsReady = false
    var events: [Ev] = []
    var turnStart: Date?
    var toolCount = 0
    var lastSummary = ""
    var seen: [String: Double] = [:]
    var hover = false
    var petUntil = Date.distantPast
    var petAcc = 0.0
    var moodSince = Date()
    var sayChangedAt = Date()

    // interaction
    var clickAt = Date.distantPast
    var dropAt = Date.distantPast
    var chatReplyAt = Date.distantPast
    var quip = ""
    var isDragging = false
    var isGliding = false
    var vx = 0.0
    var listening = false
    var chatBusy = false
    var chatOpen = false
    /// Drag, glide, and peek apply only to this slot. Mouse up clears it.
    var grabbedSid: String?
    /// Throw keeps the slot that was grabbed after mouse up clears `grabbedSid`.
    var glideSid: String?
    var chatSid: String?
    var chatStatus: ChatStatus?
    var teamDemo = false
    var bumpSids = Set<String>()
    var waveSids = Set<String>()
    var waveUntil = Date.distantPast
    var previousSids = Set<String>()
    var pokeUntil: [String: Date] = [:]
    var spinUntil: [String: Date] = [:]
    var dizzyUntil: [String: Date] = [:]
    var petSid: String?
    var leanSid: String?
    var peeking = false
    var lastClick: [String: Date] = [:]
    var clickSid: String?
    var hoverBegan: Date?
    var teamGaze: [String: Double] = [:]
    var conflictFrontSid: String?
    var conflictFile = ""
    var demo: [String] = []     // --demo: cycle through behaviours
    var ambient = AmbientMemory()
    /// One ambient memory per character, so idle clips play to the end and two Clawds don't share a roll.
    var ambientBy: [String: AmbientMemory] = [:]
    func ambientMemory(_ sid: String) -> AmbientMemory {
        if let m = ambientBy[sid] { return m }
        let m = AmbientMemory(); ambientBy[sid] = m; return m
    }
    /// Current clip and when it started, per character slot. Read by the renderer only.
    var clipTrack: [String: (name: String, start: Date)] = [:]
    /// Last drawn pose and its 12 fps frame number, per character slot (connector frames).
    var trail: [String: (pose: Pose, frame: Int)] = [:]
    var commitDay = ""
    var confettiUntil = Date.distantPast
    var sawTool100 = false
    var scale: Double = {
        let s = UserDefaults.standard.double(forKey: "scale")
        return s == 0 ? 10 : s
    }()
    /// Direction of the mouse relative to the sprite, each axis -1...1.
    var cursor: () -> CGPoint = { .zero }
    var onSound: (String) -> Void = { _ in }

    func click() {
        let quips = ["hi!", "yes?", "boop", "need me?", "♥", "ship it?", "I'm here"]
        clickAt = Date(); quip = quips.randomElement()!
        if mood == "idle" { moodSince = Date() } // wakes from sleep
    }

    /// Rebuild `sessions` from session files. Shared by the timer and `--selftest`.
    func loadSessions() {
        let fm = FileManager.default
        let now = Date().timeIntervalSince1970 * 1000
        let files = (try? fm.contentsOfDirectory(atPath: sessionsDir)) ?? []
        var parsed: [String: SessionPet] = [:]
        var fileMood: [String: String] = [:]
        for f in files where f.hasSuffix(".json") {
            let path = sessionsDir + "/" + f
            guard let data = fm.contents(atPath: path),
                  let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { continue }
            let ts = (o["ts"] as? NSNumber)?.doubleValue ?? 0
            if now - ts > 86_400_000 { try? fm.removeItem(atPath: path); continue }
            let sid = (o["sid"] as? String) ?? String(f.dropLast(5))
            let storedMood = (o["mood"] as? String) ?? "idle"
            fileMood[sid] = storedMood
            var mood = storedMood
            if mood == "working", now - ts > 900_000 { mood = "stalled" }
            let active = ["working", "waiting", "hello", "bye", "done", "oops"].contains(storedMood)
            let previous = sessions.first { $0.sid == sid }
            let lastNonIdle: Date
            if active || (previous != nil && ts > (previous?.ts ?? 0)) {
                lastNonIdle = Date()
            } else if let previous {
                lastNonIdle = previous.lastNonIdle
            } else {
                lastNonIdle = Date(timeIntervalSince1970: ts / 1000)
            }
            let toolTimes: [Double]
            if let raw = o["toolTimes"] as? [Any] {
                toolTimes = raw.compactMap { ($0 as? NSNumber)?.doubleValue }
            } else { toolTimes = [] }
            parsed[sid] = SessionPet(
                sid: sid,
                cwd: (o["cwd"] as? String) ?? "",
                project: (o["project"] as? String) ?? "",
                startedAt: (o["startedAt"] as? NSNumber)?.doubleValue ?? 0,
                transcript: (o["transcript"] as? String) ?? "",
                lastTool: (o["lastTool"] as? String) ?? "",
                toolCount: (o["toolCount"] as? NSNumber)?.intValue ?? 0,
                turnStart: (o["turnStart"] as? NSNumber)?.doubleValue,
                errorStreak: (o["errorStreak"] as? NSNumber)?.intValue ?? 0,
                lastErrorAt: (o["lastErrorAt"] as? NSNumber)?.doubleValue,
                mood: mood,
                kind: Kind(rawValue: (o["kind"] as? String) ?? "") ?? .none,
                say: (o["say"] as? String) ?? "",
                delta: (o["delta"] as? String) ?? "",
                ts: ts,
                activityId: (o["activityId"] as? String) ?? "",
                subagentCount: (o["subagentCount"] as? NSNumber)?.intValue ?? 0,
                lastDurationMs: (o["lastDurationMs"] as? NSNumber)?.doubleValue ?? 0,
                toolStartedAt: (o["toolStartedAt"] as? NSNumber)?.doubleValue,
                toolTimes: toolTimes,
                hostBundleId: (o["hostBundleId"] as? String) ?? "",
                hostPid: (o["hostPid"] as? NSNumber)?.int32Value ?? 0,
                hostApp: (o["hostApp"] as? String) ?? "",
                tty: (o["tty"] as? String) ?? "",
                lastNonIdle: lastNonIdle)
        }
        var next: [SessionPet] = []
        var kept = Set<String>()
        for s in sessions {
            guard var p = parsed[s.sid] else { continue }
            p.events = s.events
            let stored = fileMood[p.sid] ?? p.mood
            if p.ts > s.ts && (stored == "working" || stored == "waiting") && now - p.ts < 5_000 && p.kind != .think {
                let text = [p.say, p.delta].filter { !$0.isEmpty }.joined(separator: " ")
                p.events.append(Ev(ts: p.ts, kind: p.kind, text: text))
                if p.events.count > 40 { p.events = Array(p.events.suffix(40)) }
            }
            next.append(p)
            kept.insert(s.sid)
        }
        for (_, p) in parsed where !kept.contains(p.sid) {
            var fresh = p
            var text = [fresh.say, fresh.delta, fresh.lastTool].filter { !$0.isEmpty }.joined(separator: " ")
            if text.isEmpty && fresh.kind != .none && fresh.kind != .think { text = fresh.kind.rawValue }
            if !text.isEmpty { fresh.events = [Ev(ts: fresh.ts, kind: fresh.kind, text: text)] }
            next.append(fresh)
        }
        next.sort { a, b in
            if a.startedAt != b.startedAt { return a.startedAt < b.startedAt }
            return a.sid < b.sid
        }
        sessions = next
        let ids = Set(next.map(\.sid))
        if next.count >= 2 {
            let born = ids.subtracting(previousSids)
            if !previousSids.isEmpty && !born.isEmpty {
                waveSids = previousSids.intersection(ids)
                waveUntil = Date().addingTimeInterval(1.6)
            }
        } else {
            waveSids = []
        }
        if Date() > waveUntil { waveSids = [] }
        previousSids = ids
        if let look = AnimationCatalog.conflictLook(next) {
            conflictFrontSid = look.front
            conflictFile = look.file
            teamGaze = look.gaze
        } else {
            conflictFrontSid = nil
            conflictFile = ""
            teamGaze = [:]
        }
    }

    /// Waiting rows first. Each group keeps the `sessions` order (startedAt, then sid).
    var displaySessions: [SessionPet] {
        sessions.filter { $0.mood == "waiting" } + sessions.filter { $0.mood != "waiting" }
    }

    func sessionTag(_ s: SessionPet) -> String {
        let base = (s.project as NSString).lastPathComponent
        let dup = sessions.filter { ($0.project as NSString).lastPathComponent == base }.count > 1
        if dup {
            if s.cwd.isEmpty {
                let tail = String(s.sid.prefix(4))
                return base.isEmpty ? tail : "\(base)-\(tail)"
            }
            let parts = s.cwd.split(separator: "/").map(String.init).filter { !$0.isEmpty }
            if parts.count >= 2 { return parts[parts.count - 2] + "/" + parts[parts.count - 1] }
            if let only = parts.last { return only }
        }
        if !base.isEmpty { return base }
        let cwdBase = (s.cwd as NSString).lastPathComponent
        if !cwdBase.isEmpty && cwdBase != "/" { return cwdBase }
        return String(s.sid.prefix(4))
    }

    func localDay(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    /// True for the session whose `startedAt` is the earliest one today.
    func isEarliestToday(_ s: SessionPet, now: Date) -> Bool {
        let cal = Calendar.current
        let todays = sessions.filter {
            $0.startedAt > 0 && cal.isDate(Date(timeIntervalSince1970: $0.startedAt / 1000), inSameDayAs: now)
        }
        guard let best = todays.min(by: {
            if $0.startedAt != $1.startedAt { return $0.startedAt < $1.startedAt }
            return $0.sid < $1.sid
        }) else { return false }
        return best.sid == s.sid
    }

    /// Opens a 2s window for tool 100 or the first `commit` activity of the local day.
    func confettiDue(_ s: SessionPet, now: Date) -> Bool {
        let day = localDay(now)
        if s.activityId == "commit" && commitDay != day {
            commitDay = day
            confettiUntil = now.addingTimeInterval(2)
        }
        if s.toolCount == 100 && !sawTool100 {
            sawTool100 = true
            confettiUntil = now.addingTimeInterval(2)
        }
        return now < confettiUntil
    }

    func contextLine(_ s: SessionPet) -> String {
        "project: \(s.project) cwd: \(s.cwd) mood: \(s.mood) say: \(s.say) lastTool: \(s.lastTool) toolCount: \(s.toolCount)"
    }

    var accessLabel: String {
        let list = displaySessions
        if list.isEmpty { return "sleeping" }
        return list.prefix(6).map { "\(sessionTag($0)) session: \($0.mood)" }.joined(separator: ", ")
    }

    /// Cheap fingerprint of what the panel draws from the session files.
    private var lastSignature = ""
    private var signature: String {
        sessions.map { "\($0.sid)|\($0.ts)|\($0.mood)|\($0.kind.rawValue)|\($0.say)|\($0.subagentCount)" }.joined(separator: ";")
    }

    func poll() {
        loadSessions()
        // Redraw only when the files changed; the frame clock drives animation on its own.
        let sig = signature + "|\(leanSid ?? "")|\(hoveredSid ?? "")"
        if sig != lastSignature { lastSignature = sig; objectWillChange.send() }
        var sounds: [String] = []
        if moodsReady {
            for s in sessions where lastMood[s.sid] != s.mood && (s.mood == "waiting" || s.mood == "done") {
                sounds.append(s.mood)
            }
        } else if sessions.contains(where: { $0.mood == "waiting" }) {
            sounds.append("waiting")
        }
        lastMood = Dictionary(uniqueKeysWithValues: sessions.map { ($0.sid, $0.mood) })
        moodsReady = true
        if let sid = hoveredSid, let began = hoverBegan, Date().timeIntervalSince(began) >= 2 {
            leanSid = sid
        } else if hoveredSid == nil {
            leanSid = nil
        }
        soundNow = ["waiting", "done"].filter { sounds.contains($0) }
        if let s = sessions.first {
            mood = s.mood; kind = s.kind; say = s.say; delta = s.delta; project = s.project; stamp = s.ts
        } else {
            mood = "idle"; kind = .none; say = ""; delta = ""; project = ""; stamp = 0
        }
    }
}
