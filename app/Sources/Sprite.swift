import AppKit
import SwiftUI

// Clawd's proportions come from the official pixel mascot:
// body 8x6 units, arm nubs 2x2, 1x1 eyes at body cols 1 and 6, four 1-wide legs at cols 0,2,5,7.
// Sprite space: X 0..12 (arms+body+arms), Y 0..8 (body 0..6, legs 6..8).

let clawdOrange = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
let clawdDark = Color(red: 0.745, green: 0.408, blue: 0.294)     // #BE684B
let ink = Color.black

enum Eyes: Equatable { case open, tall, dash, happy, cross, squint, up }

struct Pose: Equatable {
    var dx = 0.0, lift = 0.0, sx = 1.0, sy = 1.0, tilt = 0.0
    var armL = CGPoint.zero, armR = CGPoint.zero      // units; +x moves toward the body, +y down
    var eyes = Eyes.open
    var look = CGPoint.zero
    var leg = [0.0, 0.0, 0.0, 0.0]                    // raised amount (negative = dangling)
    var legX = [0.0, 0.0, 0.0, 0.0]
    var blush = false
}

enum Beh {
    case sleep, idle(Int, Double), hello, bye, think, read, edit, bash, search, web, agent, plan, compact
    case ask, yourTurn, done, oops, listen, chatThink, chatTalk, drag, glide
    case named(String)
}

/// A pen draws in sprite units on a (possibly transformed) copy of the context.
final class Pen {
    var c: GraphicsContext
    let u: Double, ox: Double, oy: Double
    init(_ c: GraphicsContext, u: Double, ox: Double, oy: Double) { self.c = c; self.u = u; self.ox = ox; self.oy = oy }
    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ col: Color) {
        c.fill(Path(CGRect(x: ox + x * u, y: oy + y * u, width: w * u, height: h * u)), with: .color(col))
    }
    func circle(_ x: Double, _ y: Double, _ r: Double, _ col: Color) {
        c.fill(Path(ellipseIn: CGRect(x: ox + (x - r) * u, y: oy + (y - r) * u, width: 2 * r * u, height: 2 * r * u)), with: .color(col))
    }
    func ring(_ x: Double, _ y: Double, _ r: Double, _ w: Double, _ col: Color) {
        c.stroke(Path(ellipseIn: CGRect(x: ox + (x - r) * u, y: oy + (y - r) * u, width: 2 * r * u, height: 2 * r * u)),
                 with: .color(col), lineWidth: w * u)
    }
    func poly(_ pts: [(Double, Double)], _ col: Color) {
        var p = Path()
        for (i, q) in pts.enumerated() {
            let pt = CGPoint(x: ox + q.0 * u, y: oy + q.1 * u)
            if i == 0 { p.move(to: pt) } else { p.addLine(to: pt) }
        }
        p.closeSubpath(); c.fill(p, with: .color(col))
    }
    func line(_ a: CGPoint, _ b: CGPoint, _ w: Double, _ col: Color) {
        var p = Path()
        p.move(to: CGPoint(x: ox + a.x * u, y: oy + a.y * u)); p.addLine(to: CGPoint(x: ox + b.x * u, y: oy + b.y * u))
        c.stroke(p, with: .color(col), style: StrokeStyle(lineWidth: w * u, lineCap: .round))
    }
}

let sessionAccents: [Color] = [
    Color(.sRGB, red: 1, green: 1, blue: 1, opacity: 1),
    Color(.sRGB, red: 90 / 255, green: 169 / 255, blue: 1, opacity: 1),
    Color(.sRGB, red: 194 / 255, green: 139 / 255, blue: 1, opacity: 1),
    Color(.sRGB, red: 1, green: 210 / 255, blue: 90 / 255, opacity: 1),
    Color(.sRGB, red: 1, green: 122 / 255, blue: 168 / 255, opacity: 1),
    Color(.sRGB, red: 124 / 255, green: 240 / 255, blue: 200 / 255, opacity: 1),
    Color(.sRGB, red: 154 / 255, green: 167 / 255, blue: 178 / 255, opacity: 1)
]
func sessionAccent(_ name: String) -> Color {
    let sum = name.utf8.reduce(0) { $0 + Int($1) }
    return sessionAccents[sum % 7]
}

func drawClawd(_ p: Pen, _ pose: Pose, color: Color = clawdOrange, eyes: Bool = true, arms: Bool = true, accent: Color? = nil) {
    let lx = [2.0, 4.0, 7.0, 9.0]
    for i in 0..<4 {
        let h = max(0.3, 2 - pose.leg[i])
        p.rect(lx[i] + pose.legX[i], 6, 1, h, color)
    }
    p.rect(2, 0, 8, 6, color)
    if let accent { p.rect(2, 4, 8, 1, accent) }
    if arms {
        p.rect(0 + pose.armL.x, 2 + pose.armL.y, 2, 2, color)
        p.rect(10 - pose.armR.x, 2 + pose.armR.y, 2, 2, color)
    }
    guard eyes else { return }
    for ex in [3.0, 8.0] {
        let x = ex + pose.look.x, y = pose.look.y
        switch pose.eyes {
        case .open: p.rect(x, 1 + y, 1, 1, ink)
        case .tall: p.rect(x, 0.75 + y, 1, 1.6, ink)
        case .dash: p.rect(x - 0.1, 1.75, 1.2, 0.3, ink)
        case .squint: p.rect(x, 1.3 + y * 0.5, 1, 0.5, ink)
        case .up: p.rect(x, 0.7, 1, 1, ink)
        case .happy:
            p.rect(x - 0.25, 1.5, 0.5, 0.5, ink); p.rect(x + 0.25, 1.0, 0.5, 0.5, ink); p.rect(x + 0.75, 1.5, 0.5, 0.5, ink)
        case .cross:
            for (i, j) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] {
                p.rect(x - 0.25 + Double(i) * 0.5, 0.75 + Double(j) * 0.5, 0.5, 0.5, ink)
            }
        }
    }
    if pose.blush {
        p.rect(2.5, 2.3, 1.5, 0.6, Color.pink.opacity(0.6)); p.rect(8.0, 2.3, 1.5, 0.6, Color.pink.opacity(0.6))
    }
}

/// Rasterized labels. `GraphicsContext.ResolvedText` is bound to one draw, so each string is drawn once into a 2× image and reused until its text, size, weight, or color changes.
final class TextCache {
    private struct Key: Hashable {
        var string: String
        var size: Double
        var weight: Double
        var r: Double
        var g: Double
        var b: Double
        var a: Double
    }

    private var images: [Key: CGImage] = [:]

    func image(string: String, size: Double, weight: NSFont.Weight, color: NSColor) -> CGImage {
        let rgb = color.usingColorSpace(.deviceRGB) ?? color
        let key = Key(string: string, size: size, weight: Double(weight.rawValue),
                      r: Double(rgb.redComponent), g: Double(rgb.greenComponent),
                      b: Double(rgb.blueComponent), a: Double(rgb.alphaComponent))
        if let hit = images[key] { return hit }
        if images.count >= 64 { images.removeAll() }
        let made = raster(string: string, size: size, weight: weight, color: color)
        images[key] = made
        return made
    }

    func width(string: String, size: Double, weight: NSFont.Weight) -> Double {
        Double(image(string: string, size: size, weight: weight, color: .white).width) / 2
    }

    private func raster(string: String, size: Double, weight: NSFont.Weight, color: NSColor) -> CGImage {
        let point = CGFloat(size)
        let base = NSFont.systemFont(ofSize: point, weight: weight)
        let font = base.fontDescriptor.withDesign(.rounded).flatMap { NSFont(descriptor: $0, size: point) } ?? base
        let attr = NSAttributedString(string: string, attributes: [.font: font, .foregroundColor: color])
        let bounds = attr.size()
        let scale: CGFloat = 2
        let pixelsWide = max(1, Int(ceil(bounds.width * scale)))
        let pixelsHigh = max(1, Int(ceil(bounds.height * scale)))
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelsWide,
            pixelsHigh: pixelsHigh,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0)!
        rep.size = NSSize(width: CGFloat(pixelsWide) / scale, height: CGFloat(pixelsHigh) / scale)
        let host = NSImage(size: rep.size)
        host.addRepresentation(rep)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        // SwiftUI draws this CGImage right-side up. An extra y-flip made every label read upside down.
        attr.draw(with: NSRect(origin: .zero, size: rep.size), options: [.usesLineFragmentOrigin])
        NSGraphicsContext.restoreGraphicsState()
        return rep.cgImage!
    }
}

struct Renderer {
    let m: PetModel
    let confetti: [Color] = [.yellow, .pink, .cyan, .green, .orange, .purple]

    // MARK: behaviour selection
    func behavior(_ now: Date, _ t: Double, mood: String? = nil, kind: Kind? = nil, say: String? = nil, project: String? = nil, sleeping: Bool = false, session: SessionPet? = nil) -> Beh {
        let mood = mood ?? m.mood
        let kind = kind ?? m.kind
        _ = say; _ = project
        let sid = session?.sid ?? ""
        if m.teamDemo {
            let ids = ["conflictStare", "highFive", "wave", "parcel", "nap", "bump", "hop"]
            let slot = m.displaySessions.firstIndex { $0.sid == sid } ?? 0
            return .named(ids[(Int(t / 4) + slot) % ids.count])
        }
        if !m.demo.isEmpty {
            let i = Int(t / 4) % m.demo.count
            return .named(m.demo[i])
        }
        let grabbed = !sid.isEmpty && sid == m.grabbedSid
        let thrown = !sid.isEmpty && sid == (m.grabbedSid ?? m.glideSid)
        let chatting = !sid.isEmpty && sid == m.chatSid
        if grabbed && m.peeking { return .named("peek") }
        if let until = m.spinUntil[sid], now < until { return .named("spin") }
        if let until = m.pokeUntil[sid], now < until { return .named("poke") }
        if let until = m.dizzyUntil[sid], now < until { return .named("dizzy") }
        if sid == m.petSid && now < m.petUntil { return .named("pet") }
        if sid == m.leanSid { return .named("lean") }
        let sleeperChat = session == nil && m.sessions.isEmpty && m.chatOpen && m.chatStatus != nil
        if (chatting || sleeperChat), let status = m.chatStatus, m.chatOpen { return .named(status.rawValue) }
        if chatting && m.listening { return .listen }
        if chatting && m.chatBusy { return .chatThink }
        if chatting && now.timeIntervalSince(m.chatReplyAt) < 3 { return .chatTalk }
        let started = session.flatMap { $0.startedAt > 0 ? Date(timeIntervalSince1970: $0.startedAt / 1000) : nil }
        let animation = AnimationCatalog.pick(
            mood: mood, kind: kind, sleeping: sleeping,
            dragging: grabbed && m.isDragging, gliding: thrown && m.isGliding,
            reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
            now: now, memory: m.ambient,
            activityId: session?.activityId ?? "",
            subagentCount: session?.subagentCount ?? 0,
            lastDurationMs: session?.lastDurationMs ?? 0,
            toolStartedAt: session?.toolStartedAt.map { Date(timeIntervalSince1970: $0 / 1000) },
            toolTimes: session?.toolTimes ?? [],
            errorStreak: session?.errorStreak ?? 0,
            eventAt: session.map { Date(timeIntervalSince1970: $0.ts / 1000) },
            lastNonIdle: session?.lastNonIdle,
            startedAt: started,
            toolCount: session?.toolCount ?? 0,
            earliestToday: session.map { m.isEarliestToday($0, now: now) } ?? false,
            celebrate: session.map { m.confettiDue($0, now: now) } ?? false,
            sessions: m.sessions, sid: sid,
            bumping: m.bumpSids.contains(sid),
            waving: m.waveSids.contains(sid) && now < m.waveUntil)
        return .named(animation.id)
    }

    func name(_ b: Beh) -> String {
        switch b {
        case .named(let n): return n
        case .sleep: return "sleep"; case .hello: return "hello"; case .bye: return "bye"
        case .think: return "think"; case .read: return "read"; case .edit: return "edit"; case .bash: return "bash"
        case .search: return "search"; case .web: return "web"; case .agent: return "agent"; case .plan: return "plan"
        case .compact: return "compact"; case .ask: return "ask"; case .yourTurn: return "yourTurn"; case .done: return "done"
        case .oops: return "oops"; case .listen: return "listen"; case .chatThink: return "chatThink"; case .chatTalk: return "chatTalk"
        case .drag: return "drag"; case .glide: return "glide"; case .idle: return "idle"
        }
    }

    // MARK: poses
    func pose(_ name: String, quirk: Int, local: Double, t: Double, age: Double, now: Date, gaze: Double = 0) -> Pose {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return Pose() }
        var p = Pose()
        p.sy = 1 + 0.02 * sin(t * 2)
        if t.truncatingRemainder(dividingBy: 4.3) < 0.12 { p.eyes = .dash }
        let cur = m.cursor()
        p.look = CGPoint(x: cur.x * 0.5, y: cur.y * 0.25)
        let s = sin(t * 14), c = sin(t * 14 + .pi)
        let placed = AnimationCatalog.placement(id: name, elapsed: age)
        let phase = placed?.track.phase ?? "action"
        if phase == "action" {
        switch name {
        case "sleep":
            p.eyes = .dash; p.sy = 0.86 + 0.03 * sin(t * 1.1); p.tilt = 0.03 * sin(t * 0.5)
            p.armL.y = 0.5; p.armR.y = 0.5; p.look = .zero
        case "idle":
            if local >= 0 {
                switch quirk {
                case 2: p.look = CGPoint(x: 0.5 * sin(local * 2.2), y: 0.2 * sin(local * 1.3)); p.tilt = 0.04 * sin(local * 2.2)
                case 3:
                    let k = sin(local / 3 * .pi)
                    p.armL.y = -2 * k; p.armR.y = -2 * k; p.sy = 1 + 0.12 * k; if k > 0.3 { p.eyes = .dash }
                case 4:
                    let k = sin(local / 3 * .pi); p.sy = 1 + 0.07 * k; p.eyes = .dash; p.armR.y = -0.8 * k
                case 5: p.lift = abs(sin(local * 7)) * 1.6; p.armL.y = -0.6; p.armR.y = -0.6
                case 6:
                    p.leg[0] = max(0, sin(local * 14)) * 0.9; p.leg[3] = max(0, sin(local * 14 + 1.6)) * 0.9; p.look.y = 0.25
                case 7:
                    p.tilt = 0.12 * sin(local * 8); p.armL.y = sin(local * 8) * 0.8; p.armR.y = -sin(local * 8) * 0.8
                case 8:
                    p.lift = abs(sin(local * 6)) * 0.8; p.armL.y = sin(local * 6) * 1.3 - 0.5; p.armR.y = -sin(local * 6) * 1.3 - 0.5
                    p.tilt = 0.08 * sin(local * 3); p.eyes = .happy
                default: break
                }
            }
        case "hello":
            p.armR.y = -1.6 + sin(age * 12) * 0.9; p.lift = abs(sin(age * 6)) * 1.2 * max(0, 1 - age / 2.5); p.eyes = .happy
            let pop = max(0, 0.6 - age) ; p.sx = 1 + pop * 0.3; p.sy = 1 - pop * 0.2
        case "bye":
            p.armR.y = -1.6 + sin(age * 10) * 0.9; p.eyes = age > 1.6 ? .dash : .happy
        case "think":
            p.eyes = .up; p.look = CGPoint(x: 0.5 * sin(t * 1.5), y: 0); p.tilt = 0.06 * sin(t * 1.5)
            p.armR = CGPoint(x: -0.8, y: 0.9); p.lift = 0.15 + 0.15 * sin(t * 3)
        case "read":
            p.look = CGPoint(x: 0.5 * sin(t * 2.4), y: 0.2); p.armL = CGPoint(x: 1.5, y: 1.0); p.armR = CGPoint(x: 1.5, y: 1.0)
            p.leg[1] = max(0, sin(t * 3)) * 0.4
        case "edit", "bash":
            let f = name == "bash" ? 22.0 : 16.0
            p.armL = CGPoint(x: 1.3, y: 2.6 + 0.5 * sin(t * f)); p.armR = CGPoint(x: 1.3, y: 2.6 + 0.5 * sin(t * f + .pi))
            p.look = CGPoint(x: 0.3 * sin(t * 1.2), y: 0.3); p.sy = 1 + 0.02 * sin(t * 12)
        case "search":
            let lensX = sin(t * 2.2)
            p.look = CGPoint(x: lensX * 0.5, y: 0.25); p.tilt = 0.05 * lensX
            p.armR = CGPoint(x: -0.5 + lensX * 1.5, y: 1.2); p.leg[0] = max(0, s) * 0.5; p.leg[3] = max(0, c) * 0.5
        case "web":
            p.armL = CGPoint(x: 1.3, y: 1.8); p.armR = CGPoint(x: 1.3, y: 1.8); p.look = CGPoint(x: 0, y: 0.3)
            p.lift = 0.1 + 0.1 * sin(t * 4)
        case "agent":
            p.armL.y = -1 + sin(t * 5) * 0.8; p.armR.y = -1 + sin(t * 5 + .pi) * 0.8; p.eyes = .happy
            p.leg[1] = max(0, s) * 0.5; p.leg[2] = max(0, c) * 0.5
        case "test":
            p.armR = CGPoint(x: 0.4, y: 1.6); p.look = CGPoint(x: 0.4, y: 0.2); p.lift = abs(sin(t * 5)) * 0.25
        case "build":
            p.armR.y = 0.2; p.lift = abs(sin(t * 5)) * 0.3; p.eyes = sin(t * 10) > 0.85 ? .squint : .open; p.look.y = 0.25
        case "git":
            p.armR.y = -1.2 + sin(t * 3) * 0.3; p.look = CGPoint(x: 0.5, y: 0); p.tilt = 0.04 * sin(t * 2)
        case "install":
            p.armL.y = -1.8; p.armR.y = -1.8; p.eyes = .up; p.sy = 1 - 0.04 * max(0, sin(t * 7.5))
        case "pet":
            p.eyes = .happy; p.blush = true; p.tilt = 0.08 * sin(t * 7); p.sy = 1 + 0.03 * sin(t * 14)
        case "plan":
            p.armL = CGPoint(x: 1.4, y: 1.4); p.armR = CGPoint(x: 1.4, y: 1.4); p.look = CGPoint(x: 0.2 * sin(t * 2), y: 0.3)
            p.sy = 1 + 0.02 * sin(t * 3)
        case "compact":
            p.sx = 0.78 + 0.2 * sin(t * 3); p.sy = 1 + (1 - p.sx) * 0.6; p.eyes = .squint
            p.armL.y = -0.4; p.armR.y = -0.4
        case "ask":
            p.armR.y = -2.2 + sin(t * 10) * 0.7; p.lift = abs(sin(t * 5)) * 0.9; p.eyes = .tall
            p.tilt = 0.05 * sin(t * 10); p.armL.y = 0.2
        case "yourTurn":
            p.tilt = 0.1; p.armL = CGPoint(x: 1.8, y: 1.2); p.armR = CGPoint(x: 1.8, y: 1.2)
            p.leg[2] = max(0, sin(t * 8)) * 1.0
        case "done":
            p.lift = abs(sin(age * 8)) * 2.6 * max(0, 1 - age / 2)
            p.armL.y = -2 + sin(t * 14) * 0.4; p.armR.y = -2 + sin(t * 14 + 1) * 0.4; p.eyes = .happy; p.blush = true
        case "oops":
            p.dx = sin(t * 45) * 0.3 * max(0, 1 - age); p.eyes = .cross; p.sy = 0.92; p.armL.y = 0.8; p.armR.y = 0.8
        case "listen":
            p.armL = CGPoint(x: 0.2, y: -1.0); p.armR = CGPoint(x: 0.2, y: -1.0); p.eyes = .tall
            p.tilt = 0.05 * sin(t * 2); p.lift = 0.1 + 0.1 * sin(t * 6)
        case "chatThink":
            p.eyes = .up; p.look = CGPoint(x: 0.5 * sin(t * 2.3), y: 0); p.tilt = 0.09 * sin(t * 1.7)
            p.armR = CGPoint(x: -0.8, y: 0.9); p.leg[0] = max(0, s) * 0.5; p.leg[3] = max(0, c) * 0.5
        case "chatTalk":
            p.lift = abs(sin(t * 8)) * 0.5; p.armL.y = sin(t * 7) * 0.9; p.armR.y = sin(t * 7 + 2) * 0.9
            p.eyes = Int(t * 2) % 3 == 0 ? .happy : .open
        case "drag":
            p.armL.y = -1.8 + sin(t * 8) * 0.5; p.armR.y = -1.8 + sin(t * 8 + 2) * 0.5; p.eyes = .tall
            p.lift = 0.8; p.tilt = max(-0.5, min(0.5, m.vx * 0.03))
            for i in 0..<4 { p.leg[i] = -0.5; p.legX[i] = sin(t * 9 + Double(i)) * 0.45 }
        case "glide":
            p.tilt = max(-0.8, min(0.8, m.vx * 0.03)); p.eyes = .cross; p.armL.y = sin(t * 20) * 1.5; p.armR.y = -sin(t * 20) * 1.5
            p.lift = 0.6
        case "conflictStare":
            p.look = CGPoint(x: gaze, y: 0); p.eyes = .squint; p.tilt = 0.08 * gaze
        case "highFive", "wave", "hop":
            p.armR.y = -1.6 + sin(t * 10) * 0.6; p.eyes = .happy; p.lift = abs(sin(t * 6)) * 0.8
        case "parcel":
            p.armL = CGPoint(x: 1.2, y: 1.2); p.armR.y = -0.4
        case "nap":
            p.eyes = .dash; p.sy = 0.9; p.armL.y = 0.4; p.armR.y = 0.4
        case "bump":
            p.dx = sin(t * 18) * 0.4; p.sy = 0.9
        case "poke":
            p.sy = 0.86; p.eyes = .dash
        case "spin":
            p.tilt = sin(t * 14) * 0.4
        case "dizzy":
            p.eyes = .cross; p.tilt = sin(t * 12) * 0.2
        case "lean":
            p.tilt = 0.16; p.look.x = 0.4
        case "peek":
            p.look.x = 0.6; p.sx = 0.7; p.eyes = .squint
        case "opening", "listening", "reading":
            p.eyes = .tall; p.tilt = 0.05
        case "thinking":
            p.eyes = .up; p.armR = CGPoint(x: -0.6, y: 0.8)
        case "talking":
            p.armL.y = sin(t * 7) * 0.6; p.armR.y = sin(t * 7 + 1) * 0.6
        case "offline", "outOfCredits", "rateLimited", "unauthorized", "timeout":
            p.eyes = .dash; p.sy = 0.94
        case "breathe":
            p.sy = 1 + 0.02 * sin(t * 2)
        case "blink":
            p.eyes = t.truncatingRemainder(dividingBy: 1.2) < 0.15 ? .dash : .open
        case "glance":
            p.look.x = sin(t * 1.3) > 0 ? 0.7 : -0.7
        case "stretch":
            let k = max(0, sin(t * 1.5))
            p.armL.y = -2 * k; p.armR.y = -2 * k; p.sy = 1 + 0.08 * k
        case "yawn":
            p.eyes = .dash; p.lift = 0.35 + 0.2 * max(0, sin(t * 1.2)); p.armL.y = 0.3; p.armR.y = 0.3
        case "dance":
            let up = sin(t * 5) > 0
            p.armL.y = up ? -1.6 : 0.6; p.armR.y = up ? 0.6 : -1.6
        case "hum":
            p.sy = 1 + 0.025 * sin(t * 10)
        case "mote":
            p.look.x = sin(t * 1.6) * 0.5; p.armR.y = -0.8 + sin(t * 1.6) * 0.4
        case "juggle":
            let wave = sin(t * 6)
            p.armL.y = -1.4 * max(0, wave); p.armR.y = -1.4 * max(0, -wave)
        case "dream":
            p.eyes = .dash; p.sy = 0.86 + 0.03 * sin(t * 1.1); p.tilt = 0.03 * sin(t * 0.5)
            p.armL.y = 0.5; p.armR.y = 0.5; p.look = .zero
        default: break
        }
        } else if placed?.track.pose == "squash" {
            p.sy = 0.92
        } else if placed?.track.pose == "settle" {
            let dur = placed?.track.duration ?? 0
            let local = placed?.local ?? 0
            p.sy = local < dur / 2 ? 1.04 : 1
        }
        return p
    }

    /// Idle-family moods and the empty-session sleeper step at 12 fps. Drag and glide keep the raw clock.
    func presentationDate(_ now: Date, mood: String?, sleeping: Bool) -> Date {
        if m.isDragging || m.isGliding { return now }
        let key = sleeping ? "idle" : (mood ?? m.mood)
        let snap = sleeping || key == "idle" || key == "working" || key == "waiting" || key == "stalled" || key == "done"
        if !snap { return now }
        let q = 1.0 / Double(poseFPS)
        return Date(timeIntervalSinceReferenceDate: floor(now.timeIntervalSinceReferenceDate / q) * q)
    }

    func characterPose(now raw: Date, mood: String? = nil, kind: Kind? = nil, say: String? = nil, project: String? = nil, sleeping: Bool = false, session: SessionPet? = nil) -> (pose: Pose, now: Date, name: String, age: Double) {
        let now = presentationDate(raw, mood: mood, sleeping: sleeping)
        let t = now.timeIntervalSinceReferenceDate
        let beh = behavior(now, t, mood: mood, kind: kind, say: say, project: project, sleeping: sleeping, session: session)
        let bname = name(beh)
        var quirk = 0, local = -1.0
        if case .idle(let q, let l) = beh { quirk = q; local = l }
        let sinceMood = now.timeIntervalSince(m.moodSince)
        let age = m.demo.isEmpty ? sinceMood : t.truncatingRemainder(dividingBy: 4)
        let gaze = session.flatMap { m.teamGaze[$0.sid] } ?? 0
        var p = pose(bname, quirk: quirk, local: local, t: t, age: age, now: now, gaze: gaze)
        let clickAge = now.timeIntervalSince(m.clickAt)
        if session?.sid == m.clickSid && clickAge < 0.4 { p.lift += abs(sin(clickAge / 0.4 * .pi)) * 1.6 }
        let dropAge = now.timeIntervalSince(m.dropAt)
        if dropAge < 0.4 { p.sy -= 0.35 * sin(dropAge / 0.4 * .pi); p.sx += 0.15 * sin(dropAge / 0.4 * .pi) }
        if bname == "sleep" && clickAge < 2.0 { p.eyes = .open; p.sy = 1 }
        if mood == "waiting" && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            let k = 1 + 0.04 * sin(t * 4)
            p.sx *= k; p.sy *= k
        }
        return (p, now, bname, age)
    }

    /// Poses for the characters actually on screen. The empty roster uses sid `sleep`.
    func visiblePoses(at now: Date) -> [String: Pose] {
        if !m.demo.isEmpty { return ["demo": characterPose(now: now).pose] }
        let list = m.displaySessions
        if list.isEmpty { return ["sleep": characterPose(now: now, sleeping: true).pose] }
        var out: [String: Pose] = [:]
        for s in list.prefix(6) {
            out[s.sid] = characterPose(now: now, mood: s.mood, kind: s.kind, say: s.say, project: s.project, session: s).pose
        }
        return out
    }

    // MARK: main draw
    func draw(_ c: inout GraphicsContext, size: CGSize, now: Date, mood: String? = nil, kind: Kind? = nil, say: String? = nil, project: String? = nil, delta: String? = nil, accent: Color? = nil, anchorX: Double? = nil, sleeping: Bool = false, session: SessionPet? = nil) {
        let posed = characterPose(now: now, mood: mood, kind: kind, say: say, project: project, sleeping: sleeping, session: session)
        let now = posed.now
        let t = now.timeIntervalSinceReferenceDate
        let p = posed.pose
        let bname = posed.name
        let age = posed.age
        let u = m.scale
        let cx = anchorX ?? Double(size.width) / 2
        let ground = Double(size.height) - 14

        // shadow
        let sw = (11 - p.lift * 1.2) * u * p.sx
        c.fill(Path(ellipseIn: CGRect(x: cx - sw / 2 + p.dx * u, y: ground - 0.35 * u, width: sw, height: 0.9 * u)),
               with: .color(.black.opacity(max(0.05, 0.22 - p.lift * 0.04))))

        // body (transformed about the feet)
        var sc = c
        sc.translateBy(x: cx, y: ground); sc.rotate(by: .radians(p.tilt)); sc.scaleBy(x: p.sx, y: p.sy); sc.translateBy(x: -cx, y: -ground)
        let ox = cx - 6 * u + p.dx * u
        let oy = ground - 8 * u - p.lift * u
        let pen = Pen(sc, u: u, ox: ox, oy: oy)

        let isTyping = bname == "edit" || bname == "bash"
        if isTyping { drawClawd(pen, p, arms: false, accent: accent); drawLaptop(pen, bname, t); drawArms(pen, p) }
        else {
            drawClawd(pen, p, accent: accent)
            drawProp(pen, bname, p, t, front: true)
        }

        drawHat(pen, bname, t, age)
        let headX = cx + p.dx * u, headY = oy
        drawEffects(&c, bname, t: t, age: age, cx: headX, headY: headY, ground: ground, u: u, pen: pen, p: p, now: now)
        drawBubble(&c, bname, cx: headX, headY: headY, u: u, now: now, t: t, size: size, say: say, project: project, delta: delta, session: session)
        let subs = session?.subagentCount ?? 0
        if subs > 0 {
            let shown = min(4, subs)
            for i in 0..<shown {
                let mu = u * 0.35
                let mp = Pen(c, u: mu, ox: cx + (8 + Double(i) * 4.4) * u, oy: ground - 8 * mu)
                drawClawd(mp, Pose())
            }
            if subs > 4 {
                let img = m.labels.image(string: "+\(subs - 4)", size: 11, weight: .bold, color: .white)
                c.draw(Image(decorative: img, scale: 2), at: CGPoint(x: cx + (8 + 4 * 4.4) * u, y: ground - 4 * u), anchor: .center)
            }
        }
        if !m.demo.isEmpty {
            let phase = AnimationCatalog.phase(id: bname, elapsed: age)
            let text = String(format: "%@ %@ %.1f", bname, phase, age)
            let img = m.labels.image(string: text, size: 11, weight: .semibold, color: .white)
            c.draw(Image(decorative: img, scale: 2), at: CGPoint(x: cx, y: ground + 7), anchor: .center)
        }
    }

    func drawTeam(_ c: inout GraphicsContext, size: CGSize, now: Date) {
        let list = m.displaySessions
        let stride = teamStride(m.scale)
        let anchor = 8 + 6.5 * m.scale
        if list.isEmpty {
            draw(&c, size: size, now: now, anchorX: anchor, sleeping: true)
            return
        }
        let accentOn = m.sessions.count >= 2
        for (i, s) in list.prefix(6).enumerated() {
            var g = c
            g.translateBy(x: CGFloat(Double(i) * stride), y: 0)
            draw(&g, size: size, now: now, mood: s.mood, kind: s.kind, say: s.say, project: s.project, delta: s.delta, accent: accentOn ? sessionAccent(s.project) : nil, anchorX: anchor, session: s)
            drawNameTag(&g, m.sessionTag(s), cx: anchor, size: size)
        }
        let extra = list.count - 6
        if extra > 0 {
            let x = 8 + 6 * stride + 22
            let y = Double(size.height) - 14 - 4 * m.scale
            let label = m.labels.image(string: "+\(extra)", size: 13, weight: .bold, color: .white)
            c.draw(Image(decorative: label, scale: 2), at: CGPoint(x: x, y: y), anchor: .center)
        }
    }

    func drawNameTag(_ c: inout GraphicsContext, _ text: String, cx: Double, size: CGSize) {
        let pill = teamStride(m.scale) - 2
        func width(_ s: String) -> Double {
            m.labels.width(string: s, size: 9, weight: .semibold)
        }
        var label = text
        if width(label) > pill {
            let chars = Array(label)
            let minSide = 2
            if chars.count > minSide * 2 {
                var left = (chars.count + 1) / 2
                var right = chars.count - left
                while left > minSide || right > minSide {
                    if left >= right && left > minSide { left -= 1 }
                    else if right > minSide { right -= 1 }
                    else { break }
                    let candidate = String(chars.prefix(left)) + "…" + String(chars.suffix(right))
                    label = candidate
                    if width(candidate) <= pill { break }
                }
            }
        }
        guard !label.isEmpty else { return }
        let resolved = m.labels.image(string: label, size: 9, weight: .semibold, color: .white)
        let ms = Double(resolved.width) / 2
        let bw = min(ms + 8, pill), bh = 12.0
        let x = cx - bw / 2
        let y = Double(size.height) - bh - 1
        c.fill(Path(roundedRect: CGRect(x: x, y: y, width: bw, height: bh), cornerRadius: 4), with: .color(Color.black.opacity(0.55)))
        c.draw(Image(decorative: resolved, scale: 2), at: CGPoint(x: cx, y: y + bh / 2), anchor: .center)
    }

    func drawArms(_ pen: Pen, _ p: Pose) {
        pen.rect(0 + p.armL.x, 2 + p.armL.y, 2, 2, clawdOrange)
        pen.rect(10 - p.armR.x, 2 + p.armR.y, 2, 2, clawdOrange)
    }

    // MARK: props
    func drawLaptop(_ p: Pen, _ kind: String, _ t: Double) {
        let screen = Color(red: 0.11, green: 0.11, blue: 0.13), edge = Color(red: 0.32, green: 0.32, blue: 0.36)
        p.rect(2.6, 3.4, 6.8, 3.0, edge); p.rect(2.9, 3.65, 6.2, 2.5, screen)
        p.rect(2.2, 6.4, 7.6, 0.7, Color(red: 0.42, green: 0.42, blue: 0.46))
        let scroll = (t * (kind == "bash" ? 5 : 3)).truncatingRemainder(dividingBy: 1)
        for i in 0..<4 {
            let y = 3.8 + (Double(i) - scroll) * 0.6
            if y < 3.65 || y > 5.75 { continue }
            let len = 1.2 + Double((i + Int(t * (kind == "bash" ? 5 : 3))) % 4) * 0.8
            if kind == "bash" {
                p.rect(3.2, y, 0.4, 0.3, .green); p.rect(3.9, y, len, 0.3, Color.green.opacity(0.75))
            } else {
                p.rect(3.2 + Double(i % 2) * 0.5, y, len, 0.3, i % 2 == 0 ? clawdOrange : Color.white.opacity(0.8))
            }
        }
        if kind == "bash" && Int(t * 2) % 2 == 0 { p.rect(3.2, 5.6, 0.5, 0.3, .white) }
    }

    func drawProp(_ p: Pen, _ kind: String, _ pose: Pose, _ t: Double, front: Bool) {
        switch kind {
        case "read", "burstRead":
            p.rect(3.0, 2.8, 6.0, 3.6, Color.white.opacity(0.95)); p.rect(5.95, 2.8, 0.1, 3.6, Color.gray.opacity(0.6))
            let flip = Int(t * (kind == "burstRead" ? 6 : 1.2)) % 2
            for i in 0..<5 {
                let y = 3.2 + Double(i) * 0.55
                p.rect(3.4, y, flip == 0 ? 2.1 : 1.6, 0.18, Color.gray.opacity(0.6))
                p.rect(6.4, y, flip == 0 ? 1.6 : 2.2, 0.18, Color.gray.opacity(0.6))
            }
            drawArms(p, pose)
        case "plan":
            p.rect(3.6, 2.6, 4.8, 3.9, Color(red: 0.55, green: 0.38, blue: 0.22)); p.rect(3.9, 3.0, 4.2, 3.3, Color.white.opacity(0.95))
            p.rect(5.0, 2.4, 2.0, 0.6, Color.gray)
            let n = Int(t * 1.5) % 4
            for i in 0..<3 {
                let y = 3.4 + Double(i) * 0.95
                p.rect(4.2, y, 0.5, 0.5, i < n ? Color.green : Color.gray.opacity(0.4))
                p.rect(5.0, y + 0.1, 2.4, 0.2, Color.gray.opacity(0.6))
            }
            drawArms(p, pose)
        case "search":
            let lx = 6 + sin(t * 2.2) * 2.6, ly = 4.4
            drawArms(p, pose)
            p.line(CGPoint(x: lx + 1.1, y: ly + 1.1), CGPoint(x: lx + 2.3, y: ly + 2.4), 0.45, Color(red: 0.4, green: 0.3, blue: 0.2))
            p.circle(lx, ly, 1.5, Color.cyan.opacity(0.25)); p.ring(lx, ly, 1.5, 0.35, Color(white: 0.85))
        case "web":
            drawArms(p, pose)
            let gx = 6.0, gy = 4.5
            p.circle(gx, gy, 1.9, Color(red: 0.2, green: 0.5, blue: 0.9))
            for i in 0..<3 {
                let k = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                p.rect(gx - 1.6 + k * 3.2 - 0.4, gy - 0.8 + Double(i) * 0.6 - 0.2, 0.9, 0.5, Color(red: 0.3, green: 0.75, blue: 0.4))
            }
            p.ring(gx, gy, 1.9, 0.2, Color.white.opacity(0.8))
        case "test":
            drawArms(p, pose)
            let liquid = [Color.green, Color.purple, Color.cyan][Int(t / 2) % 3]
            p.rect(8.7, 2.6, 0.9, 1.3, Color.white.opacity(0.75))
            p.poly([(8.7, 3.9), (9.6, 3.9), (11.2, 6.6), (7.1, 6.6)], Color.white.opacity(0.45))
            p.poly([(8.2, 5.0), (10.1, 5.0), (11.2, 6.6), (7.1, 6.6)], liquid.opacity(0.85))
            for i in 0..<3 {
                let k = (t * 1.1 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                p.circle(8.4 + Double(i) * 0.7 + sin(t * 4 + Double(i)) * 0.15, 5.9 - k * 3.2, 0.22 + 0.1 * Double(i % 2), Color.white.opacity(0.9 * (1 - k)))
            }
        case "build":
            drawArms(p, pose)
            let a = -0.7 + sin(t * 10) * 1.0
            let pv = CGPoint(x: 11, y: 3.0 + pose.armR.y), L = 3.4
            let e = CGPoint(x: pv.x + L * sin(a), y: pv.y - L * cos(a))
            p.line(pv, e, 0.5, Color(red: 0.55, green: 0.38, blue: 0.22))
            let perp = CGPoint(x: cos(a), y: sin(a))
            p.line(CGPoint(x: e.x - perp.x * 1.0, y: e.y - perp.y * 1.0), CGPoint(x: e.x + perp.x * 1.0, y: e.y + perp.y * 1.0), 1.1, Color(white: 0.45))
        case "git":
            drawArms(p, pose)
            let nodes: [(Double, Double)] = [(13.2, 0.2), (13.2, 3.0), (13.2, 5.8), (15.2, 2.0)]
            for (a, b) in [(0, 1), (1, 2), (1, 3)] { p.line(CGPoint(x: nodes[a].0, y: nodes[a].1), CGPoint(x: nodes[b].0, y: nodes[b].1), 0.28, Color.white.opacity(0.7)) }
            for (i, n) in nodes.enumerated() {
                let on = Int(t * 2) % 4 == i
                p.circle(n.0, n.1, on ? 0.75 : 0.55, on ? Color.orange : Color.white.opacity(0.85))
            }
        case "install":
            drawArms(p, pose)
            let k = (t * 1.25).truncatingRemainder(dividingBy: 1)
            let by = -5.5 + min(1, k * 1.4) * 5.5 - (k > 0.8 ? 0.4 * sin((k - 0.8) / 0.2 * .pi) : 0)
            p.rect(4.4, by, 3.4, 2.4, Color(red: 0.75, green: 0.55, blue: 0.32))
            p.rect(5.8, by, 0.6, 2.4, Color(red: 0.9, green: 0.8, blue: 0.55)); p.rect(4.4, by + 0.9, 3.4, 0.25, Color.black.opacity(0.2))
        case "deploy":
            drawArms(p, pose)
            p.poly([(6, 1.2), (7.2, 3.2), (4.8, 3.2)], Color.white.opacity(0.9))
        case "commit":
            drawArms(p, pose)
            p.circle(9.2, 2.2, 1.1, Color(red: 0.75, green: 0.15, blue: 0.18))
            p.circle(9.2, 2.2, 0.45, Color.white.opacity(0.85))
        case "push":
            drawArms(p, pose)
            p.poly([(8.2, 2.6), (11.4, 1.6), (10.2, 3.4)], Color(red: 0.35, green: 0.6, blue: 0.9))
        case "pull":
            drawArms(p, pose)
            p.rect(8.4, 1.6, 2.4, 1.8, Color(red: 0.55, green: 0.38, blue: 0.22))
        case "lint":
            drawArms(p, pose)
            p.line(CGPoint(x: 8.4, y: 1.4), CGPoint(x: 11.2, y: 3.6), 0.45, Color(red: 0.85, green: 0.55, blue: 0.7))
        case "migrate":
            drawArms(p, pose)
            p.rect(8.2, 3.2, 2.2, 1.2, Color(red: 0.45, green: 0.55, blue: 0.75))
            p.rect(8.6, 2.0, 2.2, 1.1, Color(red: 0.55, green: 0.65, blue: 0.85))
            p.rect(9.0, 0.9, 2.2, 1.0, Color(red: 0.65, green: 0.75, blue: 0.9))
        case "docker":
            drawArms(p, pose)
            p.rect(8.2, 1.8, 2.6, 2.2, Color(red: 0.2, green: 0.55, blue: 0.85))
        case "serve":
            drawArms(p, pose)
            p.rect(8.6, 2.4, 1.6, 1.8, Color(red: 0.9, green: 0.7, blue: 0.3))
            p.circle(9.4, 1.6, 0.45, Color.yellow.opacity(0.9))
        case "mcp":
            drawArms(p, pose)
            p.line(CGPoint(x: 8.2, y: 2.4), CGPoint(x: 11.0, y: 2.4), 0.35, .white)
        case "notebook":
            drawArms(p, pose)
            p.rect(3.2, 2.6, 5.6, 3.4, Color.white.opacity(0.95))
        case "webSearch":
            drawArms(p, pose)
            p.circle(9.2, 2.4, 1.2, Color.cyan.opacity(0.35))
            p.ring(9.2, 2.4, 1.2, 0.25, .white)
        case "webFetch":
            drawArms(p, pose)
            p.rect(8.0, 1.4, 2.8, 3.2, Color.white.opacity(0.92))
            p.rect(8.4, 1.9, 2.0, 0.2, Color.gray.opacity(0.6))
            p.rect(8.4, 2.4, 1.6, 0.2, Color.gray.opacity(0.6))
        case "bandage":
            drawArms(p, pose)
            p.rect(3.2, 2.4, 5.6, 1.1, Color.white.opacity(0.9))
        case "sweat":
            drawArms(p, pose)
            p.circle(9.4, 1.2, 0.45, Color.cyan.opacity(0.85))
        case "tea", "coffee":
            drawArms(p, pose)
            p.rect(8.4, 2.2, 2.2, 1.6, kind == "coffee" ? Color(red: 0.45, green: 0.28, blue: 0.16) : Color(red: 0.7, green: 0.85, blue: 0.75))
            p.rect(10.4, 2.6, 0.7, 0.9, .white.opacity(0.8))
        case "book":
            drawArms(p, pose)
            p.rect(8.2, 1.6, 2.8, 3.4, Color(red: 0.35, green: 0.45, blue: 0.7))
        case "frantic":
            drawArms(p, pose)
            p.line(CGPoint(x: 12.2, y: 1.2), CGPoint(x: 14.2, y: 1.6), 0.25, .white.opacity(0.8))
            p.line(CGPoint(x: 12.4, y: 2.4), CGPoint(x: 14.6, y: 2.6), 0.25, .white.opacity(0.7))
            p.line(CGPoint(x: 12.2, y: 3.6), CGPoint(x: 14.0, y: 3.8), 0.25, .white.opacity(0.6))
        case "watch":
            drawArms(p, pose)
            p.circle(9.4, 2.2, 1.15, .white.opacity(0.15))
            p.ring(9.4, 2.2, 1.15, 0.22, .white)
        case "flag":
            drawArms(p, pose)
            p.line(CGPoint(x: 8.6, y: 1.0), CGPoint(x: 8.6, y: 4.2), 0.25, .white)
            p.rect(8.6, 1.0, 2.2, 1.3, Color.orange)
        case "nightcap":
            drawArms(p, pose)
            p.circle(9.6, 1.4, 1.0, Color(white: 0.92))
            p.circle(10.1, 1.1, 0.85, Color(red: 0.12, green: 0.12, blue: 0.16))
        case "conflict":
            drawArms(p, pose)
            p.line(CGPoint(x: 8.2, y: 1.4), CGPoint(x: 10.6, y: 3.6), 0.35, Color.red)
            p.line(CGPoint(x: 10.6, y: 1.4), CGPoint(x: 8.2, y: 3.6), 0.35, Color.red)
        default:
            drawArms(p, pose)
        }
        _ = front
    }

    func drawHat(_ p: Pen, _ b: String, _ t: Double, _ age: Double) {
        let dark = Color(white: 0.16)
        switch b {
        case "read":
            for ex in [2.6, 7.6] { p.rect(ex, 0.55, 1.8, 0.2, .white); p.rect(ex, 2.15, 1.8, 0.2, .white); p.rect(ex, 0.55, 0.2, 1.8, .white); p.rect(ex + 1.6, 0.55, 0.2, 1.8, .white) }
            p.rect(4.4, 1.3, 3.2, 0.2, .white)
        case "edit":
            p.rect(2.6, -0.7, 6.8, 0.4, dark); p.rect(1.7, 0.9, 1.0, 2.2, dark); p.rect(9.3, 0.9, 1.0, 2.2, dark)
            p.rect(1.8, 1.3, 0.6, 1.4, clawdOrange); p.rect(9.6, 1.3, 0.6, 1.4, clawdOrange)
        case "bash":
            p.rect(2.3, -1.5, 7.4, 1.5, dark); p.rect(2.3, -0.5, 7.4, 0.5, Color(white: 0.28)); p.rect(5.0, -1.9, 2.0, 0.4, dark)
            p.rect(3.0, -1.0, 0.5, 0.3, Color.green)
        case "search":
            p.rect(1.8, -0.5, 8.4, 0.5, Color(red: 0.45, green: 0.3, blue: 0.18)); p.rect(3.0, -2.0, 6.0, 1.5, Color(red: 0.55, green: 0.38, blue: 0.22))
            p.rect(3.0, -1.0, 6.0, 0.3, Color(red: 0.3, green: 0.2, blue: 0.12))
        case "web":
            p.rect(1.5, -0.4, 9.0, 0.4, Color(red: 0.85, green: 0.72, blue: 0.45)); p.rect(3.2, -1.7, 5.6, 1.4, Color(red: 0.9, green: 0.78, blue: 0.5))
            p.rect(3.2, -0.9, 5.6, 0.35, Color(red: 0.7, green: 0.2, blue: 0.2))
        case "agent":
            let gold = Color(red: 0.98, green: 0.8, blue: 0.2)
            p.rect(3.0, -1.0, 6.0, 1.0, gold)
            for x in [3.0, 5.4, 7.8] { p.rect(x, -2.0, 1.2, 1.0, gold) }
            p.rect(5.6, -0.6, 0.8, 0.5, Color.red)
        case "build":
            let y = Color(red: 0.98, green: 0.78, blue: 0.1)
            p.rect(2.6, -1.8, 6.8, 1.8, y); p.rect(1.9, -0.4, 8.2, 0.5, y); p.rect(5.3, -2.3, 1.4, 0.5, y)
        case "test":
            p.rect(2.6, 0.5, 2.4, 2.1, Color.cyan.opacity(0.35)); p.rect(7.0, 0.5, 2.4, 2.1, Color.cyan.opacity(0.35))
            p.rect(2.6, 0.5, 6.8, 0.25, Color(white: 0.9)); p.rect(5.0, 1.3, 2.0, 0.25, Color(white: 0.9))
        case "plan":
            p.rect(9.2, -0.6, 0.5, 2.0, Color.yellow); p.rect(9.2, -0.9, 0.5, 0.3, Color.pink)
        case "sleep":
            p.poly([(3.0, 0.0), (8.5, 0.0), (9.8, -1.0), (10.6, 0.6), (6.5, -1.6)], Color(red: 0.75, green: 0.2, blue: 0.2))
            p.circle(10.6, 0.9, 0.55, .white); p.rect(2.6, -0.4, 6.2, 0.5, .white)
        case "oops":
            p.rect(6.0, -0.3, 3.2, 1.0, Color(red: 0.92, green: 0.8, blue: 0.62)); p.rect(7.4, 0.0, 0.3, 0.3, Color(white: 0.5))
        case "install":
            p.rect(2.8, -1.2, 6.4, 1.2, Color(red: 0.2, green: 0.4, blue: 0.7)); p.rect(2.8, -0.3, 8.2, 0.4, Color(red: 0.2, green: 0.4, blue: 0.7))
        case "done":
            let k = min(1, max(0, (age - 0.5) / 0.35))
            if k > 0 {
                let y = 0.6 - (1 - k) * 5
                p.rect(2.6, y, 3.0, 1.6, ink); p.rect(6.4, y, 3.0, 1.6, ink); p.rect(5.6, y, 0.8, 0.35, ink)
                p.rect(3.0, y + 0.2, 0.9, 0.3, Color.white.opacity(0.6)); p.rect(6.8, y + 0.2, 0.9, 0.3, Color.white.opacity(0.6))
            }
        default: break
        }
    }

    static let quips: [String: [String]] = [
        "think": ["pondering…", "brain whirring", "connecting dots", "hold that thought", "consulting the vibes", "thinking really hard"],
        "read": ["skimming the juicy bits", "reading the fine print", "speed-reading", "studying the evidence", "ooh, what's this?"],
        "edit": ["rewriting history", "tidying things up", "typing very fast", "surgical edits", "moving semicolons around", "making it better"],
        "bash": ["summoning the shell", "let's see if it explodes", "fingers crossed", "terminal wizardry", "bash go brrr"],
        "search": ["on the hunt", "grepping the haystack", "where did it go?", "detective mode", "following a hunch"],
        "web": ["surfing the web", "asking the internet", "fetching knowledge", "one sec, googling"],
        "agent": ["calling in backup", "delegating", "my little helpers", "team effort"],
        "plan": ["making a plan", "ticking boxes", "organizing the chaos", "so many todos"],
        "compact": ["squeezing my memory", "tidying up context", "making room"],
        "test": ["science time", "do the tests pass?", "red or green?", "testing, testing"],
        "build": ["hammering away", "building it up", "assembling bits"],
        "git": ["version control time", "branching out", "committing to it", "pushing buttons"],
        "install": ["unpacking deps", "delivery incoming", "fetching packages"],
        "ask": ["psst, need your OK", "permission pls?", "your call, boss", "waiting on you"],
        "yourTurn": ["your turn", "ready when you are", "ball's in your court"],
        "done": ["all done!", "nailed it", "ta-da!", "done and dusted"],
        "oops": ["oops", "that didn't go well", "uh oh", "it broke!"],
        "hello": ["hi there!", "let's go!", "ready to help"],
        "bye": ["see ya", "bye!"],
    ]
    func pick(_ k: String) -> String {
        let pool = Renderer.quips[k] ?? [k]
        return pool[abs(Int(m.stamp / 7)) % pool.count]
    }

    // MARK: effects
    func drawEffects(_ c: inout GraphicsContext, _ b: String, t: Double, age: Double, cx: Double, headY: Double, ground: Double, u: Double, pen: Pen, p: Pose, now: Date) {
        func glyph(_ s: String, _ x: Double, _ y: Double, _ size: Double, _ col: Color) {
            let img = m.labels.image(string: s, size: size, weight: .bold, color: NSColor(col))
            c.draw(Image(decorative: img, scale: 2), at: CGPoint(x: x, y: y))
        }
        switch b {
        case "think", "chatThink":
            if Int(t / 3) % 3 == 0 && (t.truncatingRemainder(dividingBy: 3)) > 2.2 { glyph("💡", cx + 5.2 * u, headY - 0.6 * u, 22, .yellow) }
            for i in 0..<3 {
                let k = max(0, sin(t * 5 - Double(i) * 0.9)), r = (0.35 + 0.35 * k) * u
                c.fill(Path(ellipseIn: CGRect(x: cx + (Double(i) * 1.4 + 3) * u - r, y: headY - (0.6 + Double(i) * 0.6) * u - r, width: 2 * r, height: 2 * r)),
                       with: .color(.white.opacity(0.9)))
            }
        case "confetti":
            for i in 0..<6 {
                let a = t * 3 + Double(i) * 1.05
                var d = c; d.translateBy(x: cx + cos(a) * 7 * u, y: headY + 2 * u + sin(a) * 3 * u); d.rotate(by: .radians(a))
                d.fill(Path(CGRect(x: -0.4 * u, y: -0.4 * u, width: 0.8 * u, height: 0.8 * u)), with: .color(confetti[i % 6].opacity(0.9)))
            }
        case "edit", "bash", "read", "plan", "search":
            for i in 0..<3 {
                let a = t * 2.4 + Double(i) * 2.094
                var d = c; d.translateBy(x: cx + cos(a) * 8 * u, y: headY + 3 * u + sin(a) * 2.6 * u); d.rotate(by: .radians(a * 2))
                d.fill(Path(CGRect(x: -0.35 * u, y: -0.35 * u, width: 0.7 * u, height: 0.7 * u)), with: .color(confetti[(i * 2) % 6].opacity(0.85)))
            }
        case "web":
            for i in 0..<3 {
                let k = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                c.stroke(Path { $0.addArc(center: CGPoint(x: cx, y: headY - 0.2 * u), radius: (1.5 + k * 3) * u, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false) },
                         with: .color(.cyan.opacity(0.9 * (1 - k))), lineWidth: 0.35 * u)
            }
        case "agent":
            for (i, side) in [-1.0, 1.0].enumerated() {
                let mu = u * 0.3
                let hop = abs(sin(t * 6 + Double(i) * 2)) * 1.5
                let mp = Pen(c, u: mu, ox: cx + side * 9.5 * u - 6 * mu, oy: ground - 8 * mu - hop * mu * 2)
                var mpose = Pose(eyes: .happy); mpose.armL.y = -1; mpose.armR.y = -1
                drawClawd(mp, mpose, color: clawdOrange.opacity(0.95))
            }
        case "compact":
            for side in [-1.0, 1.0] {
                let k = 0.5 + 0.5 * sin(t * 3)
                glyph(side < 0 ? "▶" : "◀", cx + side * (6.2 + k * 1.2) * u, headY + 3 * u, 14, .white.opacity(0.85))
            }
        case "ask":
            for i in 0..<2 {
                let k = (t * 0.9 + Double(i) * 0.5).truncatingRemainder(dividingBy: 1)
                c.stroke(Path(ellipseIn: CGRect(x: cx - (3 + k * 7) * u, y: ground - (0.4 + k * 1.4) * u, width: (6 + k * 14) * u, height: (0.8 + k * 2.8) * u)),
                         with: .color(clawdOrange.opacity(0.8 * (1 - k))), lineWidth: 2)
            }
            let pulse = 1 + 0.15 * sin(t * 8)
            glyph("?", cx + 5.4 * u, headY - 0.2 * u, 22 * pulse, Color.yellow)
        case "yourTurn":
            glyph("…", cx + 5.5 * u, headY - 0.1 * u, 20, .white.opacity(0.5 + 0.5 * sin(t * 4)))
        case "done":
            if age < 2 {
                for i in 0..<20 {
                    let a = Double(i) * 2.399, sp = 70.0 + Double(i % 5) * 22
                    var d = c; d.translateBy(x: cx + cos(a) * sp * age, y: headY - 10 - abs(sin(a)) * sp * 1.1 * age + 150 * age * age)
                    d.rotate(by: .radians(age * 8 + Double(i)))
                    d.fill(Path(CGRect(x: -3, y: -2, width: 6, height: 4)), with: .color(confetti[i % 6].opacity(max(0, 1 - age / 2))))
                }
            }
            glyph("✓", cx + 5.5 * u, headY - 0.2 * u, 22, Color.green)
        case "oops":
            let k = (t * 1.2).truncatingRemainder(dividingBy: 1)
            c.fill(Path(ellipseIn: CGRect(x: cx + 4.6 * u, y: headY + 0.2 * u + k * 2.5 * u, width: 0.9 * u, height: 1.3 * u)), with: .color(Color.cyan.opacity(0.85 * (1 - k * 0.6))))
            for i in 0..<3 {
                let k2 = (t * 0.8 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                c.fill(Path(ellipseIn: CGRect(x: cx - 1.5 * u + sin(t * 2 + Double(i)) * u, y: headY - k2 * 4 * u, width: 1.1 * u * (1 + k2), height: 1.1 * u * (1 + k2))),
                       with: .color(Color.gray.opacity(0.5 * (1 - k2))))
            }
            glyph("!", cx - 5 * u, headY, 20, Color.red)
        case "sleep":
            for i in 0..<3 {
                let ph = (t * 0.35 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                glyph("z", cx + 5 * u + ph * 3.2 * u, headY - ph * 4.5 * u + 1.5 * u, 9 + ph * 10, .white.opacity(1 - ph))
            }
        case "listen":
            for i in 0..<3 {
                let k = (t * 1.1 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                for side in [-1.0, 1.0] {
                    c.stroke(Path { $0.addArc(center: CGPoint(x: cx + side * 7.2 * u, y: headY + 3 * u), radius: (1 + k * 3.5) * u, startAngle: .degrees(side < 0 ? 140 : -40), endAngle: .degrees(side < 0 ? 220 : 40), clockwise: false) },
                             with: .color(Color.red.opacity(0.9 * (1 - k))), lineWidth: 0.4 * u)
                }
            }
        case "chatTalk":
            for i in 0..<3 {
                let k = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                glyph(i % 2 == 0 ? "♪" : "♫", cx + (Double(i) - 1) * 3 * u + sin(t * 3 + Double(i)) * 8, headY - k * 4.5 * u, 16, Color.pink.opacity(1 - k))
            }
        case "pet":
            for i in 0..<4 {
                let k = (t * 0.9 + Double(i) / 4).truncatingRemainder(dividingBy: 1)
                glyph("♥", cx + (Double(i) - 1.5) * 2.4 * u + sin(t * 3 + Double(i)) * 5, headY - 0.5 * u - k * 5 * u, 15, .pink.opacity(1 - k))
            }
        case "build":
            if sin(t * 10) > 0.8 {
                for i in 0..<5 {
                    let a = Double(i) * 1.2
                    glyph("✦", cx + 6.6 * u + cos(a) * 20, headY + 5.3 * u - abs(sin(a)) * 20, 10, .yellow)
                }
            }
        case "hello":
            glyph("✦", cx - 5.2 * u, headY + 0.5 * u + sin(t * 8) * 3, 16, .yellow)
        case "glide":
            for i in 0..<3 { glyph("✦", cx + sin(t * 9 + Double(i) * 2) * 6 * u, headY - Double(i) * u, 12, .yellow.opacity(0.8)) }
        case "mote":
            pen.rect(8 + sin(t * 1.6) * 2.5, -1.2 + cos(t * 1.6) * 0.6, 1, 1, .white.opacity(0.9))
        case "dream":
            pen.ring(6, -1.8, 1.3, 0.18, .white.opacity(0.8))
        default:
            if b == "idle" {
                // idle quirks carry little extras
                let q = abs((Int(floor(t / 9)) &* 2654435761) >> 4) % 9
                let local = t - floor(t / 9) * 9 - 2
                if q == 8 && local >= 0 && local < 4 {
                    for i in 0..<2 {
                        let k = (t * 1.2 + Double(i) / 2).truncatingRemainder(dividingBy: 1)
                        glyph("♪", cx + (Double(i) * 2 - 1) * 4 * u, headY - k * 3.5 * u, 15, Color.pink.opacity(1 - k))
                    }
                }
            }
        }
        // long hard work: a bead of sweat
        if (b == "edit" || b == "bash" || b == "think" || b == "read") && now.timeIntervalSince(m.moodSince) > 150 && m.demo.isEmpty {
            let k = (t * 0.6).truncatingRemainder(dividingBy: 1)
            c.fill(Path(ellipseIn: CGRect(x: cx + 4.4 * u, y: headY + 0.4 * u + k * 2.5 * u, width: 0.8 * u, height: 1.1 * u)), with: .color(Color.cyan.opacity(0.8 * (1 - k * 0.5))))
        }
        // click hearts
        let ca = now.timeIntervalSince(m.clickAt)
        if ca < 1.6 {
            for i in 0..<3 {
                let k = ca / 1.6
                glyph("♥", cx + (Double(i) - 1) * 2.2 * u + sin(t * 4 + Double(i)) * 4, headY - 0.5 * u - k * 5 * u - Double(i) * 6, 14, .pink.opacity(1 - k))
            }
        }
    }

    // MARK: speech bubble
    func drawBubble(_ c: inout GraphicsContext, _ b: String, cx: Double, headY: Double, u: Double, now: Date, t: Double, size: CGSize, say: String? = nil, project: String? = nil, delta: String? = nil, session: SessionPet? = nil) {
        var text = "", sub = "", fill = Color(white: 0.1, opacity: 0.9)
        var since = m.sayChangedAt
        let ca = now.timeIntervalSince(m.clickAt)
        if m.chatOpen && !m.listening { return }
        if b == "conflictStare", let session, session.sid == m.conflictFrontSid, !m.conflictFile.isEmpty {
            text = "conflict: \(m.conflictFile)"
            since = Date(timeIntervalSince1970: session.ts / 1000)
        }
        let say = say ?? m.say
        let project = project ?? m.project
        let delta = delta ?? m.delta
        let detail = say + (delta.isEmpty ? "" : "  " + delta)
        if text.isEmpty {
        if !m.demo.isEmpty { text = b }
        else if ca < 2.0 && session?.sid == m.clickSid { text = m.quip; since = m.clickAt }
        else {
            switch b {
            case "ask": text = pick("ask"); sub = say.isEmpty ? project : say; fill = Color(red: 0.62, green: 0.3, blue: 0.1, opacity: 0.95)
            case "yourTurn": text = pick("yourTurn"); sub = project
            case "think", "read", "edit", "bash", "search", "web", "agent", "plan", "compact", "test", "build", "git", "install": text = pick(b); sub = detail
            case "done": text = pick("done"); sub = m.lastSummary.isEmpty ? project : m.lastSummary; fill = Color(red: 0.12, green: 0.4, blue: 0.22, opacity: 0.95)
            case "oops": text = pick("oops"); sub = project; fill = Color(red: 0.55, green: 0.16, blue: 0.14, opacity: 0.95)
            case "hello": text = pick("hello"); sub = project
            case "bye": text = pick("bye")
            case "pet": text = "purrr…"
            case "listen": text = "listening…"; fill = Color(red: 0.6, green: 0.15, blue: 0.15, opacity: 0.95)
            case "chatThink": text = "hmm…"
            default: break
            }
        }
        }
        if text.isEmpty { return }
        if text.count > 38 { text = String(text.prefix(37)) + "…" }
        if sub.count > 44 { sub = String(sub.prefix(43)) + "…" }
        let pop = min(1, now.timeIntervalSince(since) / 0.18)
        let main = m.labels.image(string: text, size: 12, weight: .semibold, color: .white)
        let subR = m.labels.image(string: sub, size: 10, weight: .medium, color: NSColor.white.withAlphaComponent(0.6))
        let ms = CGSize(width: CGFloat(main.width) / 2, height: CGFloat(main.height) / 2)
        let ss = sub.isEmpty ? CGSize.zero : CGSize(width: CGFloat(subR.width) / 2, height: CGFloat(subR.height) / 2)
        let bw = max(ms.width, ss.width) + 22, bh = ms.height + (sub.isEmpty ? 0 : ss.height + 1) + 12
        var bx = cx - bw / 2
        bx = max(4, min(Double(size.width) - bw - 4, bx))
        let by = max(4, headY - 1.8 * u - bh - 6)
        var g = c
        g.translateBy(x: cx, y: by + bh); g.scaleBy(x: 0.6 + 0.4 * pop, y: 0.6 + 0.4 * pop); g.translateBy(x: -cx, y: -(by + bh))
        g.opacity = pop
        g.fill(Path(roundedRect: CGRect(x: bx, y: by, width: bw, height: bh), cornerRadius: 11), with: .color(fill))
        var tail = Path()
        tail.move(to: CGPoint(x: cx - 5, y: by + bh - 0.5)); tail.addLine(to: CGPoint(x: cx + 5, y: by + bh - 0.5)); tail.addLine(to: CGPoint(x: cx, y: by + bh + 6))
        g.fill(tail, with: .color(fill))
        if sub.isEmpty { g.draw(Image(decorative: main, scale: 2), at: CGPoint(x: bx + bw / 2, y: by + bh / 2), anchor: .center) }
        else {
            g.draw(Image(decorative: main, scale: 2), at: CGPoint(x: bx + bw / 2, y: by + 6 + ms.height / 2), anchor: .center)
            g.draw(Image(decorative: subR, scale: 2), at: CGPoint(x: bx + bw / 2, y: by + 7 + ms.height + ss.height / 2), anchor: .center)
        }
    }
}

/// Single character clock. 12 fps, or 60 fps while dragging or gliding. Skips publishing when asleep, occluded, or the visible pose has not changed.
final class FrameClock: ObservableObject {
    @Published var now = Date()
    weak var panel: NSPanel?
    var asleep = false
    private var timer: Timer?
    private var model: PetModel?
    private var fast = false
    private var poseCache: [String: Pose] = [:]
    private var sleepNotes: [NSObjectProtocol] = []

    func start(_ model: PetModel) {
        self.model = model
        let nc = NSWorkspace.shared.notificationCenter
        sleepNotes.append(nc.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = true
        })
        sleepNotes.append(nc.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.asleep = false
        })
        schedule(fast: false)
    }

    /// Drag and glide need the shorter interval immediately, not on the next idle tick.
    func retune() {
        let want = model?.isDragging == true || model?.isGliding == true
        if want != fast { schedule(fast: want) }
    }

    private func schedule(fast: Bool) {
        self.fast = fast
        timer?.invalidate()
        let interval = fast ? 1.0 / 60 : 1 / Double(poseFPS)
        let t = Timer(timeInterval: interval, repeats: true) { [weak self] _ in self?.tick() }
        timer = t
        RunLoop.main.add(t, forMode: .common)
    }

    private func tick() {
        guard let model else { return }
        let wantFast = model.isDragging || model.isGliding
        if wantFast != fast { schedule(fast: wantFast) }
        if asleep { return }
        guard let panel, panel.occlusionState.contains(.visible) else { return }
        let raw = Date()
        let poses = Renderer(m: model).visiblePoses(at: raw)
        if !wantFast && poses == poseCache { return }
        poseCache = poses
        now = raw
    }
}

struct PetView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var clock: FrameClock
    var body: some View {
        Canvas { ctx, size in
            let r = Renderer(m: model)
            let now = clock.now
            if model.demo.isEmpty { r.drawTeam(&ctx, size: size, now: now) }
            else { r.draw(&ctx, size: size, now: now) }
        }
        .frame(width: CGFloat(teamPanelWidth(count: model.sessions.count, scale: model.scale)), height: canvasH)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.demo.isEmpty ? model.accessLabel : model.demo[Int(clock.now.timeIntervalSinceReferenceDate / 4) % model.demo.count])
    }
}
