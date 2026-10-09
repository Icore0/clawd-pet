import Foundation

struct Track {
    var phase: String
    var duration: Double
    var pose: String
}

struct Animation {
    var id: String
    var trigger: String
    var detected: String
    var priority: Int
    var duration: Double
    var loop: Bool
    var props: String
    var sound: String
    var status: String
    var windUp: Double
    var settle: Double
    var tracks: [Track]
    var instant: Bool = false
    var instantReason: String = ""
}

struct Placement {
    var track: Track
    var local: Double
}

/// One remembered ambient id. `pick` will not hand that id back until 20s have passed.
final class AmbientMemory {
    var lastId = ""
    var chosenAt = Date.distantPast
}

enum AnimationCatalog {
    static let waitingPriority = 60
    static let errorPriority = 50
    static let eventPriority = 40
    static let activityPriority = 30
    static let idlePriority = 20
    static let ambientPriority = 10

    static let activityIds: Set<String> = [
        "read", "edit", "bash", "search", "web", "agent", "plan", "compact",
        "test", "build", "git", "install", "ask", "done", "oops", "hello", "bye"
    ]
    static let ambientIds: Set<String> = [
        "breathe", "glance", "stretch", "yawn", "dance", "hum", "juggle", "dream"
    ]

    static let ambientWeights: [(String, Int)] = [
        ("breathe", 6), ("glance", 3), ("stretch", 2), ("yawn", 2),
        ("dance", 1), ("hum", 2), ("juggle", 1), ("dream", 1)
    ]

    static let all: [Animation] = [
        clip("read", "read", "mood working, kind read", activityPriority, action: 2.4, loop: true, pose: "eyes", props: "book"),
        clip("edit", "edit", "mood working, kind edit", activityPriority, action: 1.6, loop: true, pose: "arms", props: "laptop"),
        clip("search", "search", "mood working, kind search", activityPriority, action: 1.4, loop: true, pose: "lean", props: "glass"),
        clip("web", "web", "mood working, kind web", activityPriority, action: 2.0, loop: true, pose: "eyes", props: "page"),
        clip("agent", "agent", "mood working, kind agent", activityPriority, action: 1.6, loop: true, pose: "arms"),
        clip("plan", "plan", "mood working, kind plan", activityPriority, action: 2.2, loop: true, pose: "arms"),
        clip("test", "test", "mood working, kind test", activityPriority, action: 2.0, loop: true, pose: "eyes"),
        clip("build", "build", "mood working, kind build", activityPriority, action: 2.6, loop: true, pose: "arms", wind: 0.40, settle: 0.50),
        clip("git", "git", "mood working, kind git", activityPriority, action: 1.2, loop: true, pose: "lean"),
        clip("install", "install", "mood working, kind install", activityPriority, action: 2.2, loop: true, pose: "arms"),
        clip("ask", "waiting", "mood waiting, kind is not yourTurn", waitingPriority, action: 1.4, loop: true, pose: "arms"),
        clip("done", "done", "mood done", eventPriority, action: 0.8, loop: false, pose: "arms"),
        clip("oops", "oops", "mood oops", errorPriority, action: 1.0, loop: true, pose: "squash"),
        clip("hello", "hello", "mood hello", eventPriority, action: 0.8, loop: false, pose: "arms"),
        clip("bye", "bye", "mood bye", eventPriority, action: 0.8, loop: false, pose: "arms"),
        clip("think", "working", "mood working, kind has no activity entry", activityPriority, action: 1.5, loop: true, pose: "eyes"),
        clip("breathe", "ambient", "weighted idle pool", ambientPriority, action: 3.2, loop: true, pose: "squash"),
        clip("glance", "ambient", "weighted idle pool", ambientPriority, action: 1.2, loop: true, pose: "eyes"),
        clip("stretch", "ambient", "weighted idle pool, or a 2h session for 3s every 10min", ambientPriority, action: 1.6, loop: true, pose: "arms"),
        clip("yawn", "ambient", "weighted idle pool", ambientPriority, action: 1.8, loop: true, pose: "eyes"),
        clip("dance", "ambient", "weighted idle pool", ambientPriority, action: 1.4, loop: true, pose: "arms"),
        clip("hum", "ambient", "weighted idle pool", ambientPriority, action: 2.0, loop: true, pose: "squash"),
        clip("juggle", "ambient", "weighted idle pool", ambientPriority, action: 1.6, loop: true, pose: "arms"),
        clip("dream", "ambient", "weighted idle pool", ambientPriority, action: 3.0, loop: true, pose: "eyes"),
        clip("sleep", "sleep", "sleeping flag, or idle 120s", idlePriority, action: 4.0, loop: true, pose: "eyes"),
        clip("drag", "drag", "isDragging", eventPriority, action: 0.8, loop: true, pose: "arms"),
        clip("pet", "pet", "petUntil still ahead", eventPriority, action: 0.9, loop: true, pose: "eyes"),
        clip("listen", "listen", "listening", eventPriority, action: 1.3, loop: true, pose: "eyes"),
        clip("chatThink", "chatThink", "chatBusy", eventPriority, action: 1.7, loop: true, pose: "eyes"),
        clip("chatTalk", "chatTalk", "chat reply younger than 3s", eventPriority, action: 1.5, loop: true, pose: "arms"),
        clip("testPass", "testPass", "a test command finished, first 2.5s", eventPriority, action: 2.2, loop: false, pose: "arms", props: "check"),
        clip("testFail", "testFail", "a test command failed, first 2.5s", errorPriority, action: 2.0, loop: false, pose: "squash", props: "x"),
        clip("handoff", "handoff", "a sub-agent started, first 2.5s", eventPriority, action: 1.4, loop: false, pose: "arms", props: "parcel"),
        clip("grind", "grind", "working turn longer than 20 min, 3s every 5 min", eventPriority, action: 3.0, loop: false, pose: "arms"),
        clip("deploy", "deploy", "command vercel, netlify, fly deploy, npm publish, or docker push", activityPriority, action: 1.8, loop: true, pose: "arms", props: "mark", wind: 0.45, settle: 0.55),
        clip("push", "push", "command git push", activityPriority, action: 1.3, loop: true, pose: "lean", props: "plane"),
        clip("pull", "pull", "command git pull or git fetch", activityPriority, action: 1.5, loop: true, pose: "arms", props: "parcel"),
        clip("webSearch", "webSearch", "WebSearch", activityPriority, action: 1.8, loop: true, pose: "eyes", props: "glass"),
        clip("sweat", "sweat", "tool running longer than 60s", eventPriority, action: 1.1, loop: true, pose: "lean", props: "drop"),
        clip("tea", "tea", "tool running longer than 180s", eventPriority, action: 2.5, loop: true, pose: "arms", props: "cup"),
        clip("frantic", "frantic", "15 tool starts inside 10s", eventPriority, action: 0.5, loop: true, pose: "arms", props: "lines", wind: 0.05, settle: 0.08),
        clip("watch", "watch", "waiting longer than 120s", waitingPriority, action: 1.6, loop: true, pose: "eyes", props: "circle"),
        clip("flag", "flag", "waiting longer than 600s", waitingPriority, action: 1.4, loop: true, pose: "lean", props: "flag"),
        clip("confetti", "confetti", "tool 100 or first commit today, 2s", eventPriority, action: 1.4, loop: false, pose: "arms", props: "dots"),
        clip("nightcap", "nightcap", "idle, local hour 1 through 4", idlePriority, action: 2.6, loop: true, pose: "eyes", props: "moon"),
        clip("conflict", "conflict", "failure text has CONFLICT or Automatic merge failed", errorPriority, action: 1.0, loop: false, pose: "squash", props: "mark"),
        clip("highFive", "team", "two done moods within 3s", eventPriority, action: 0.8, loop: false, pose: "arms", wind: 0.15, settle: 0.25),
        clip("wave", "team", "a session sid newly appeared", eventPriority, action: 0.9, loop: false, pose: "arms", wind: 0.12, settle: 0.22),
        clip("parcel", "team", "done while another session works, then sleep", eventPriority, action: 1.1, loop: false, pose: "arms", props: "parcel", wind: 0.35, settle: 0.40),
        clip("nap", "team", "every session idle for 120s", idlePriority, action: 2.0, loop: true, pose: "eyes", wind: 0.50, settle: 0.60),
        clip("hop", "team", "every session mood is done", eventPriority, action: 0.7, loop: true, pose: "arms", wind: 0.10, settle: 0.18),
        clip("dizzy", "dizzy", "hold and shake", eventPriority, action: 1.0, loop: false, pose: "eyes", wind: 0.09, settle: 0.16),
        clip("offline", "chat", "chat status offline", eventPriority, action: 1.0, loop: true, pose: "eyes"),
        clip("outOfCredits", "chat", "chat status outOfCredits", eventPriority, action: 1.0, loop: true, pose: "eyes"),
        clip("rateLimited", "chat", "chat status rateLimited", eventPriority, action: 1.0, loop: true, pose: "eyes"),
        clip("timeout", "chat", "chat status timeout", eventPriority, action: 1.0, loop: true, pose: "eyes")
    ]

    /// Clips folded into a clearer one. Every old trigger still lands on a real clip.
    static let aliases: [String: String] = [
        "bash": "edit",
        "compact": "think",
        "yourTurn": "ask",
        "blink": "breathe",
        "mote": "glance",
        "glide": "drag",
        "commit": "git",
        "lint": "edit",
        "migrate": "build",
        "docker": "install",
        "serve": "build",
        "mcp": "web",
        "burstRead": "read",
        "notebook": "edit",
        "webFetch": "web",
        "bandage": "oops",
        "book": "tea",
        "coffee": "tea",
        "conflictStare": "conflict",
        "bump": "hop",
        "poke": "hop",
        "spin": "dizzy",
        "lean": "glance",
        "peek": "drag",
        "opening": "listen",
        "listening": "listen",
        "reading": "chatThink",
        "thinking": "chatThink",
        "talking": "chatTalk",
        "unauthorized": "offline"
    ]
    static func resolve(_ id: String) -> String { aliases[id] ?? id }

    /// Id lookup, built once (the renderer asks several times per frame per character).
    static let index: [String: Animation] = Dictionary(all.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    static func byId(_ id: String) -> Animation {
        index[resolve(id)] ?? all[0]
    }

    /// Walks tracks. A looping action stays in that track after anticipation; a one-shot continues into settle.
    static func placement(id: String, elapsed: Double) -> Placement? {
        guard let anim = index[id], !anim.tracks.isEmpty, !anim.instant else { return nil }
        let t = max(0, elapsed)
        if anim.loop {
            let anti = anim.tracks.first { $0.phase == "anticipation" }
            let antiDur = anti?.duration ?? 0
            if t < antiDur, let anti { return Placement(track: anti, local: t) }
            if let action = anim.tracks.first(where: { $0.phase == "action" }) {
                let into = action.duration > 0 ? (t - antiDur).truncatingRemainder(dividingBy: action.duration) : 0
                return Placement(track: action, local: into)
            }
        }
        var acc = 0.0
        for track in anim.tracks {
            if t < acc + track.duration { return Placement(track: track, local: t - acc) }
            acc += track.duration
        }
        guard let last = anim.tracks.last else { return nil }
        return Placement(track: last, local: max(0, t - (anim.duration)))
    }

    static func phase(id: String, elapsed: Double) -> String {
        placement(id: id, elapsed: elapsed)?.track.phase ?? "action"
    }

    static func markdown() -> String {
        var lines = [
            "| id | trigger | how detected | priority | duration | loop | props | sound | status | tracks |",
            "|---|---|---|---|---|---|---|---|---|---|"
        ]
        for anim in all {
            let tracks = anim.tracks.map { "\($0.phase) \(tenth($0.duration))" }.joined(separator: ", ")
            let loop = anim.loop ? "yes" : "no"
            lines.append("| \(anim.id) | \(anim.trigger) | \(anim.detected) | \(anim.priority) | \(tenth(anim.duration)) | \(loop) | \(anim.props) | \(anim.sound) | \(anim.status) | \(tracks) |")
        }
        return lines.joined(separator: "\n") + "\n"
    }

    /// First match wins. Ambient roll is an integer mix of `now`, so the same timestamp always picks the same id.
    /// `toolTimes` and `toolStartedAt` are milliseconds-since-1970 and an absolute date. `is_interrupt` is not an input.
    static func pick(
        mood: String,
        kind: Kind,
        sleeping: Bool = false,
        dragging: Bool = false,
        gliding: Bool = false,
        reduceMotion: Bool = false,
        now: Date = Date(),
        memory: AmbientMemory = AmbientMemory(),
        activityId: String = "",
        subagentCount: Int = 0,
        lastDurationMs: Double = 0,
        toolStartedAt: Date? = nil,
        toolTimes: [Double] = [],
        errorStreak: Int = 0,
        eventAt: Date? = nil,
        lastNonIdle: Date? = nil,
        startedAt: Date? = nil,
        toolCount: Int = 0,
        earliestToday: Bool = false,
        celebrate: Bool = false,
        sessions: [SessionPet] = [],
        sid: String = "",
        bumping: Bool = false,
        waving: Bool = false,
        turnStart: Date? = nil
    ) -> Animation {
        _ = subagentCount
        _ = lastDurationMs
        if dragging { return byId("drag") }
        if gliding { return byId("glide") }
        if let team = teamChoice(sid: sid, sessions: sessions, now: now, bumping: bumping, waving: waving) {
            return byId(team)
        }
        if sleeping { return byId("sleep") }
        // Short reactions to one event: they play once, then the session's normal clip takes over.
        if ["testPass", "testFail", "handoff"].contains(activityId), let eventAt, now.timeIntervalSince(eventAt) < 2.5 {
            return byId(activityId)
        }
        if mood == "waiting", let eventAt {
            let waited = now.timeIntervalSince(eventAt)
            if waited > 600 { return byId("flag") }
            if waited > 120 { return byId("watch") }
        }
        if errorStreak >= 3 { return byId("bandage") }
        if let toolStartedAt {
            let age = now.timeIntervalSince(toolStartedAt)
            if age > 600 { return byId("book") }
            if age > 180 { return byId("tea") }
            if age > 60 { return byId("sweat") }
        }
        let nowMs = now.timeIntervalSince1970 * 1000
        if toolTimes.filter({ nowMs - $0 < 10_000 }).count >= 15 { return byId("frantic") }
        if mood == "working", let turnStart, now.timeIntervalSince(turnStart) > 1_200,
           now.timeIntervalSince1970.truncatingRemainder(dividingBy: 300) < 3 {
            return byId("grind")
        }
        if !activityId.isEmpty, !["testPass", "testFail", "handoff"].contains(activityId), index[resolve(activityId)] != nil {
            return byId(activityId)
        }
        if mood == "waiting" { return byId(kind == .yourTurn ? "yourTurn" : "ask") }
        if mood == "oops" { return byId("oops") }
        if mood == "hello" || mood == "bye" || mood == "done" { return byId(mood) }
        if mood == "working" {
            if activityIds.contains(kind.rawValue) { return byId(kind.rawValue) }
            return byId("think")
        }
        if let startedAt, now.timeIntervalSince(startedAt) > 7_200 {
            let into = now.timeIntervalSince1970.truncatingRemainder(dividingBy: 600)
            if into < 3 { return byId("stretch") }
        }
        if earliestToday, let startedAt, now.timeIntervalSince(startedAt) < 30 { return byId("coffee") }
        if celebrate { return byId("confetti") }
        if startedAt != nil, mood == "idle" {
            let hour = Calendar.current.component(.hour, from: now)
            if (1...4).contains(hour) { return byId("nightcap") }
        }
        if mood == "idle", let lastNonIdle, now.timeIntervalSince(lastNonIdle) > 120 { return byId("sleep") }
        if reduceMotion { return byId("breathe") }
        return ambient(now: now, memory: memory)
    }

    static func runChecks() -> String? {
        if pick(mood: "waiting", kind: .read).id != "ask" { return "waiting over read" }
        if pick(mood: "working", kind: .read).id != "read" { return "working over read" }
        if pick(mood: "oops", kind: .read).id != "oops" { return "oops over read" }
        // Ambient clips play to the end (no flip-flop between frames) and never repeat back to back.
        let memory = AmbientMemory()
        var ids: [String] = []
        var current = "", since = Date.distantPast
        for i in 0..<(12 * 120) {
            let now = Date(timeIntervalSinceReferenceDate: 10_000 + Double(i) / 12)
            let id = pick(mood: "idle", kind: .none, now: now, memory: memory).id
            if id != current {
                if !current.isEmpty && now.timeIntervalSince(since) + 0.0001 < byId(current).duration { return "ambient \(current) cut short" }
                if id == current { return "ambient repeated \(id)" }
                ids.append(id); current = id; since = now
            }
        }
        for i in 1..<ids.count where ids[i] == ids[i - 1] { return "ambient back to back \(ids[i])" }
        if Set(ids).count < 3 { return "ambient variety" }
        for anim in all {
            if anim.instant {
                if anim.instantReason.isEmpty { return "\(anim.id) instant needs a reason" }
                continue
            }
            let phases = Set(anim.tracks.map(\.phase))
            if !phases.contains("anticipation") || !phases.contains("settle") { return "\(anim.id) missing anticipation or settle" }
            let sum = anim.tracks.reduce(0) { $0 + $1.duration }
            if abs(sum - anim.duration) > 0.001 { return "\(anim.id) duration" }
        }
        let fixed = Date(timeIntervalSince1970: 1_700_000_000)
        if pick(mood: "idle", kind: .none, now: fixed, errorStreak: 3).id != "oops" { return "error streak oops" }
        if pick(mood: "working", kind: .bash, now: fixed, toolStartedAt: fixed.addingTimeInterval(-61)).id != "sweat" { return "tool 61s sweat" }
        if pick(mood: "working", kind: .bash, now: fixed, toolStartedAt: fixed.addingTimeInterval(-181)).id != "tea" { return "tool 181s tea" }
        if let problem = independenceCheck() { return problem }
        return nil
    }

    /// Values on a tenth stay one decimal. Anything finer keeps two, so 0.05 does not collapse to 0.0.
    private static func tenth(_ d: Double) -> String {
        let scaled = d * 10
        if abs(scaled - scaled.rounded()) < 0.001 { return String(format: "%.1f", d) }
        return String(format: "%.2f", d)
    }

    private static func clip(
        _ id: String, _ trigger: String, _ detected: String, _ priority: Int,
        action: Double, loop: Bool, pose: String, props: String = "", status: String = "done",
        wind: Double = 0.20, settle: Double = 0.30
    ) -> Animation {
        // The action track lasts exactly as long as the hand-authored frames.
        let action = AnimationData.clips[id].map { Double($0.frameCount) / 12 } ?? action
        let tracks = [
            Track(phase: "anticipation", duration: wind, pose: "squash"),
            Track(phase: "action", duration: action, pose: pose),
            Track(phase: "settle", duration: settle, pose: "settle")
        ]
        return Animation(
            id: id, trigger: trigger, detected: detected, priority: priority,
            duration: tracks.reduce(0) { $0 + $1.duration },
            loop: loop, props: props, sound: "", status: status, windUp: wind, settle: settle, tracks: tracks)
    }

    struct SlotBox {
        var x = 0.0, y = 0.0, w = 0.0, h = 0.0
        func hits(_ o: SlotBox) -> Bool {
            x < o.x + o.w && o.x < x + w && y < o.y + o.h && o.y < y + h
        }
    }

    static func bumpSids(grabbed: String, frames: [String: SlotBox]) -> Set<String> {
        guard frames.count >= 2, let mine = frames[grabbed] else { return [] }
        var hits = Set<String>()
        for (sid, box) in frames where sid != grabbed && mine.hits(box) {
            hits.insert(grabbed)
            hits.insert(sid)
        }
        return hits
    }

    static func conflictLook(_ sessions: [SessionPet]) -> (front: String, back: String, file: String, gaze: [String: Double])? {
        guard sessions.count >= 2 else { return nil }
        for i in sessions.indices {
            for j in sessions.indices where j > i {
                let a = sessions[i], b = sessions[j]
                guard a.kind == .edit, b.kind == .edit else { continue }
                let fa = (a.say as NSString).lastPathComponent
                let fb = (b.say as NSString).lastPathComponent
                guard !fa.isEmpty, fa == fb, abs(a.ts - b.ts) <= 60_000 else { continue }
                return (a.sid, b.sid, fa, [a.sid: 0.8, b.sid: -0.8])
            }
        }
        return nil
    }

    /// Team ids only when at least two sessions exist. `now` is injectable so checks do not read the clock.
    static func teamChoice(sid: String, sessions: [SessionPet], now: Date, bumping: Bool, waving: Bool) -> String? {
        guard sessions.count >= 2 else { return nil }
        if bumping { return "bump" }
        if let me = sessions.first(where: { $0.sid == sid }), me.kind == .edit {
            let file = (me.say as NSString).lastPathComponent
            let peers = sessions.filter {
                $0.kind == .edit && ($0.say as NSString).lastPathComponent == file && abs($0.ts - me.ts) <= 60_000 && !file.isEmpty
            }
            if peers.count >= 2 { return "conflictStare" }
        }
        if let me = sessions.first(where: { $0.sid == sid }), me.mood == "done" {
            let peerDone = sessions.contains { $0.sid != sid && $0.mood == "done" && abs($0.ts - me.ts) <= 3_000 }
            if peerDone { return "highFive" }
            if sessions.allSatisfy({ $0.mood == "done" }) { return "hop" }
            if sessions.contains(where: { $0.sid != sid && $0.mood == "working" }) {
                let age = now.timeIntervalSince1970 * 1000 - me.ts
                return age < 2_000 ? "parcel" : "sleep"
            }
        }
        if sessions.allSatisfy({ $0.mood == "done" }) { return "hop" }
        if sessions.allSatisfy({ $0.mood == "idle" && now.timeIntervalSince($0.lastNonIdle) >= 120 }) { return "nap" }
        if waving { return "wave" }
        return nil
    }

    static func independenceCheck() -> String? {
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        func row(_ sid: String, _ mood: String, _ kind: Kind, _ say: String, _ ts: Double, idle: Double = 0) -> SessionPet {
            var s = SessionPet(sid: sid, cwd: "", project: sid, startedAt: 1, transcript: "", lastTool: "", toolCount: 0, turnStart: nil, errorStreak: 0, lastErrorAt: nil, mood: mood, kind: kind, say: say, delta: "", ts: ts)
            s.lastNonIdle = now.addingTimeInterval(-idle)
            return s
        }
        let ms = now.timeIntervalSince1970 * 1000
        let three = [row("a", "working", .read, "a", ms), row("b", "working", .read, "b", ms), row("c", "working", .read, "c", ms)]
        for sid in ["a", "b", "c"] {
            let dragging = sid == "b"
            let id = pick(mood: "working", kind: .read, dragging: dragging, now: now, sessions: three, sid: sid).id
            if sid == "b" {
                if id != "drag" { return "grabbed sid b not drag" }
            } else if id == "drag" {
                return "drag leaked to \(sid)"
            }
        }
        let team = ["conflictStare", "highFive", "wave", "parcel", "nap", "bump", "hop"]
        let solo = [row("a", "working", .edit, "App.swift", ms)]
        let soloId = pick(mood: "working", kind: .edit, now: now, sessions: solo, sid: "a", bumping: true, waving: true).id
        if team.contains(soloId) { return "team with one session" }
        if teamChoice(sid: "a", sessions: solo, now: now, bumping: true, waving: true) != nil { return "teamChoice with one session" }

        let stare = [row("a", "working", .edit, "src/App.swift", ms), row("b", "working", .edit, "lib/App.swift", ms + 1_000)]
        if pick(mood: "working", kind: .edit, now: now, sessions: stare, sid: "a").id != "conflict" { return "conflict stare a" }
        if pick(mood: "working", kind: .edit, now: now, sessions: stare, sid: "b").id != "conflict" { return "conflict stare b" }
        if pick(mood: "working", kind: .edit, dragging: true, now: now, sessions: stare, sid: "a").id != "drag" { return "drag loses to stare" }
        if conflictLook(stare)?.file != "App.swift" { return "conflict file" }
        let late = [row("a", "working", .edit, "src/App.swift", ms), row("b", "working", .edit, "lib/App.swift", ms + 61_000)]
        if pick(mood: "working", kind: .edit, now: now, sessions: late, sid: "a").id == "conflict" { return "conflict too late" }

        let fived = [row("a", "done", .none, "", ms), row("b", "done", .none, "", ms + 1_000), row("c", "working", .read, "", ms)]
        if pick(mood: "done", kind: .none, now: now, sessions: fived, sid: "a").id != "highFive" { return "high five a" }
        if pick(mood: "done", kind: .none, now: now, sessions: fived, sid: "b").id != "highFive" { return "high five b" }
        if pick(mood: "working", kind: .read, now: now, sessions: fived, sid: "c").id == "highFive" { return "high five c" }

        let hopped = [row("a", "done", .none, "", ms), row("b", "done", .none, "", ms + 10_000)]
        if pick(mood: "done", kind: .none, now: now, sessions: hopped, sid: "a").id != "hop" { return "hop" }

        let fresh = [row("a", "done", .none, "", ms - 200), row("b", "working", .read, "", ms)]
        if pick(mood: "done", kind: .none, now: now, sessions: fresh, sid: "a").id != "parcel" { return "parcel" }
        let older = [row("a", "done", .none, "", ms - 5_000), row("b", "working", .read, "", ms)]
        if pick(mood: "done", kind: .none, now: now, sessions: older, sid: "a").id != "sleep" { return "parcel sleep" }

        let napping = [row("a", "idle", .none, "", ms, idle: 121), row("b", "idle", .none, "", ms, idle: 130)]
        if pick(mood: "idle", kind: .none, now: now, sessions: napping, sid: "a").id != "nap" { return "nap" }

        let waking = [row("a", "working", .read, "", ms), row("b", "working", .bash, "", ms)]
        if pick(mood: "working", kind: .read, now: now, sessions: waking, sid: "a", waving: true).id != "wave" { return "wave" }
        if pick(mood: "working", kind: .read, now: now, sessions: waking, sid: "a", bumping: true).id != "hop" { return "bump a" }
        if pick(mood: "working", kind: .bash, now: now, sessions: waking, sid: "b", bumping: true).id != "hop" { return "bump b" }
        let boxes = ["a": SlotBox(x: 0, y: 0, w: 10, h: 10), "b": SlotBox(x: 5, y: 0, w: 10, h: 10)]
        let hit = bumpSids(grabbed: "a", frames: boxes)
        if hit != ["a", "b"] { return "bump overlap" }
        if !bumpSids(grabbed: "a", frames: ["a": SlotBox(x: 0, y: 0, w: 10, h: 10)]).isEmpty { return "bump one" }

        if byId("frantic").windUp != 0.05 || byId("frantic").settle != 0.08 { return "frantic timing" }
        if byId("build").windUp != 0.40 || byId("build").settle != 0.50 { return "build timing" }
        if byId("deploy").windUp != 0.45 || byId("deploy").settle != 0.55 { return "deploy timing" }
        if all.allSatisfy({ abs($0.windUp - 0.20) < 0.0001 && abs($0.settle - 0.30) < 0.0001 }) { return "uniform wind-up" }
        for anim in all where !anim.instant {
            let wind = anim.tracks.first { $0.phase == "anticipation" }?.duration
            let settle = anim.tracks.first { $0.phase == "settle" }?.duration
            if wind != anim.windUp || settle != anim.settle { return "\(anim.id) track timing" }
        }
        let doneClips = ["deploy", "push", "pull", "webSearch"]
        for id in doneClips where byId(id).status != "done" { return "\(id) status" }
        if all.contains(where: { $0.id == "alarm" }) { return "alarm has no verified trigger" }
        let ev = Date(timeIntervalSince1970: 1_700_000_000)
        if pick(mood: "working", kind: .think, now: ev.addingTimeInterval(1), activityId: "testPass", eventAt: ev).id != "testPass" { return "test pass" }
        if pick(mood: "working", kind: .think, now: ev.addingTimeInterval(3), activityId: "testPass", eventAt: ev).id == "testPass" { return "test pass lingers" }
        if pick(mood: "working", kind: .think, now: ev.addingTimeInterval(1), activityId: "testFail", eventAt: ev).id != "testFail" { return "test fail" }
        if pick(mood: "working", kind: .agent, now: ev.addingTimeInterval(1), activityId: "handoff", eventAt: ev).id != "handoff" { return "handoff" }
        if pick(mood: "working", kind: .agent, now: ev.addingTimeInterval(4), activityId: "handoff", eventAt: ev).id != "agent" { return "handoff lingers" }
        for anim in all where anim.id != "glide" && AnimationData.clips[anim.id] == nil { return "\(anim.id) has no frame data" }
        func named(_ command: String) -> String {
            activityName(tool: "Bash", input: ["command": command], previousTool: "", toolTimes: [], now: 0)
        }
        if named("echo vercel") != "" { return "echo vercel" }
        if named("git commit-tree") != "" { return "git commit-tree" }
        if named("vercel --prod") != "deploy" { return "vercel" }
        if named("netlify deploy") != "deploy" { return "netlify" }
        if named("fly deploy") != "deploy" { return "fly" }
        if named("npm publish") != "deploy" { return "npm publish" }
        if named("docker push") != "deploy" { return "docker push" }
        if named("git commit -m hi") != "commit" { return "git commit" }
        if named("git push") != "push" { return "git push" }
        if named("git pull") != "pull" { return "git pull" }
        if named("git fetch") != "pull" { return "git fetch" }
        if named("eslint .") != "lint" { return "eslint" }
        if named("prettier .") != "lint" { return "prettier" }
        if named("ruff check") != "lint" { return "ruff" }
        if named("prisma migrate") != "migrate" { return "prisma" }
        if named("alembic upgrade head") != "migrate" { return "alembic" }
        if named("psql db") != "migrate" { return "psql" }
        if named("docker build .") != "docker" { return "docker" }
        if named("compose up") != "docker" { return "compose" }
        if named("npm run dev") != "serve" { return "npm run dev" }
        if named("uvicorn app:app") != "serve" { return "uvicorn" }
        if activityName(tool: "WebSearch", input: [:], previousTool: "", toolTimes: [], now: 0) != "webSearch" { return "webSearch" }
        if activityName(tool: "WebFetch", input: [:], previousTool: "", toolTimes: [], now: 0) != "webFetch" { return "webFetch" }
        if activityName(tool: "NotebookEdit", input: [:], previousTool: "", toolTimes: [], now: 0) != "notebook" { return "notebook" }
        if activityName(tool: "mcp__x", input: [:], previousTool: "", toolTimes: [], now: 0) != "mcp" { return "mcp" }
        if activityName(tool: "Read", input: [:], previousTool: "Read", toolTimes: [0, 1, 2], now: 2) != "burstRead" { return "burstRead" }
        if let problem = commandFixtureCheck() { return problem }
        return nil
    }

    /// `fixtures/commands.jsonl` is the command-clip contract. Each line carries `expect`.
    static func commandFixtureCheck() -> String? {
        let fm = FileManager.default
        var dir = fm.currentDirectoryPath
        var path: String?
        for _ in 0..<6 {
            let candidate = dir + "/fixtures/commands.jsonl"
            if fm.fileExists(atPath: candidate) { path = candidate; break }
            let parent = (dir as NSString).deletingLastPathComponent
            if parent == dir { break }
            dir = parent
        }
        guard let path else { return "commands.jsonl missing" }
        guard let text = try? String(contentsOfFile: path, encoding: .utf8) else { return "commands.jsonl unreadable" }
        for (index, line) in text.split(separator: "\n").enumerated() {
            guard let data = line.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return "commands.jsonl line \(index)" }
            let tool = (obj["tool_name"] as? String) ?? ""
            let input = (obj["tool_input"] as? [String: Any]) ?? [:]
            let expect = (obj["expect"] as? String) ?? ""
            let got = activityName(tool: tool, input: input, previousTool: "", toolTimes: [], now: 0)
            if got != expect { return "commands.jsonl \(index) want \(expect) got \(got)" }
        }
        return nil
    }

    /// Keeps the current ambient clip until it has played once, then rolls a different one.
    private static func ambient(now: Date, memory: AmbientMemory) -> Animation {
        if !memory.lastId.isEmpty, now >= memory.chosenAt, now.timeIntervalSince(memory.chosenAt) < byId(memory.lastId).duration {
            return byId(memory.lastId)
        }
        let total = ambientWeights.reduce(0) { $0 + $1.1 }
        let roll = abs(Int(now.timeIntervalSinceReferenceDate) &* 1103515245) % total
        var acc = 0
        var idx = 0
        for (i, pair) in ambientWeights.enumerated() {
            acc += pair.1
            if roll < acc { idx = i; break }
        }
        if ambientWeights[idx].0 == memory.lastId { idx = (idx + 1) % ambientWeights.count }
        let id = ambientWeights[idx].0
        memory.lastId = id
        memory.chosenAt = now
        return byId(id)
    }
}
