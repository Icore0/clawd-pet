import AppKit
import SwiftUI

// Wigglet's proportions come from the official pixel mascot:
// body 8x6 units, arm nubs 2x2, 1x1 eyes at body cols 1 and 6, four 1-wide legs at cols 0,2,5,7.
// Sprite space: X 0..12 (arms+body+arms), Y 0..8 (body 0..6, legs 6..8).

let wiggletOrange = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
let wiggletDark = Color(red: 0.745, green: 0.408, blue: 0.294)     // #BE684B
let ink = Color.black

enum Eyes: Equatable { case open, tall, closed, happy, cross, spiral }
enum Mouth: Equatable { case none, smile, open, o, yawn, wavy, flat }
/// `.right` faces right: the back (left) column darkens and both eyes shift toward the front, as in the official turn.
/// `.back` is the turned-away frame used mid-spin: no eyes, both side columns dark.
enum Profile: Equatable { case none, left, right, back }

/// Whole sprite pixels (24 x 16 grid). `lean` shifts the body sideways (max 2). `squash` lowers the head, keeping the feet down.
/// `crouch` sits the body down two pixels onto short legs. `fade` 1...4 removes pixels in a fixed dither (pop-in, fade-out), never alpha.
struct Pose: Equatable {
    var lean = 0
    var squash = 0
    var lift = 0
    var dx = 0
    var armLX = 0, armLY = 0
    var armRX = 0, armRY = 0
    var eyes = Eyes.open
    var mouth = Mouth.none
    var lookX = 0, lookY = 0
    var leg = [0, 0, 0, 0]
    var legX = [0, 0, 0, 0]
    var blush = false
    var profile = Profile.none
    var crouch = false
    var fade = 0

    func with(_ f: (inout Pose) -> Void) -> Pose { var p = self; f(&p); return p }
}

/// What a recorded cell belongs to. Only the frame audit reads this.
enum CellLayer: Int { case body, arm, leg, eye, prop, hat, fx }

enum Beh {
    case sleep, idle(Int, Double), hello, bye, think, read, edit, bash, search, web, agent, plan, compact
    case ask, yourTurn, done, oops, listen, chatThink, chatTalk, drag, glide
    case named(String)
}

/// Cell pen. `u` is a whole number of points. The backing scale only snaps those cells onto whole device pixels.
final class Pen {
    var c: GraphicsContext?
    let u: Double, ox: Double, oy: Double
    let device: Double
    var recording = false
    var problem: String?
    var scale = 1.0
    var rotation = 0.0
    var cells: [Int: [Int: UInt32]] = [:]
    /// Layer tag for the next rects, and every cell each layer touched (recording pens only).
    var layer = CellLayer.body
    var layerCells: [CellLayer: Set<Int>] = [:]
    /// 0 draws everything. 1...3 drop more cells in a fixed dither, so a fade stays on the grid.
    var fade = 0
    static func key(_ x: Int, _ y: Int) -> Int { (y + 512) * 4096 + (x + 2048) }

    func masked(_ x: Int, _ y: Int) -> Bool {
        switch fade {
        case 1: return (x + 2 * y) % 4 == 0
        case 2: return (x + y) % 2 == 0
        case 3: return !((x % 2 == 0) && (y % 2 == 0)) || (x + y) % 4 == 0
        case let f where f >= 4: return true
        default: return false
        }
    }

    init(_ c: GraphicsContext, u: Double, ox: Double, oy: Double) {
        self.c = c
        // Sprite pixels may be half points; `rect` snaps them onto device pixels.
        self.u = max(0.5, (u * 2).rounded() / 2)
        self.ox = ox
        self.oy = oy
        self.device = Double(NSScreen.main?.backingScaleFactor ?? 2)
    }

    init(recordingU u: Double) {
        self.c = nil
        self.u = max(1, u.rounded())
        self.ox = 0
        self.oy = 0
        self.device = 1
        self.recording = true
    }

    func markScale(_ s: Double) { if s != 1 { problem = problem ?? "scale" }; scale = s }
    func markRotation(_ r: Double) { if r != 0 { problem = problem ?? "rotation" }; rotation = r }

    func rect(_ x: Double, _ y: Double, _ w: Double, _ h: Double, _ col: Color) {
        let integral = x.isFinite && y.isFinite && w.isFinite && h.isFinite && x == x.rounded() && y == y.rounded() && w == w.rounded() && h == h.rounded() && w >= 1 && h >= 1
        if !integral { problem = problem ?? "non-integer" }
        let ix = Int(x.rounded())
        let iy = Int(y.rounded())
        let iw = max(1, Int(w.rounded()))
        let ih = max(1, Int(h.rounded()))
        let s = device
        let px0 = ((ox + Double(ix) * u) * s).rounded() / s
        let py0 = ((oy + Double(iy) * u) * s).rounded() / s
        let pw = max(1.0 / s, (Double(iw) * u * s).rounded() / s)
        let ph = max(1.0 / s, (Double(ih) * u * s).rounded() / s)
        if fade > 0 {
            for yy in iy..<(iy + ih) {
                for xx in ix..<(ix + iw) where !masked(((xx % 64) + 64) % 64, ((yy % 64) + 64) % 64) {
                    let cx0 = ((ox + Double(xx) * u) * s).rounded() / s, cy0 = ((oy + Double(yy) * u) * s).rounded() / s
                    let cw = max(1.0 / s, (u * s).rounded() / s)
                    c?.fill(Path(CGRect(x: cx0, y: cy0, width: cw, height: cw)), with: .color(col), style: FillStyle(antialiased: false))
                }
            }
        } else {
            let path = Path(CGRect(x: px0, y: py0, width: pw, height: ph))
            c?.fill(path, with: .color(col), style: FillStyle(antialiased: false))
        }
        if recording {
            let packed = Pen.pack(col)
            var set = layerCells[layer] ?? []
            for yy in iy..<(iy + ih) {
                for xx in ix..<(ix + iw) {
                    if fade > 0 && masked(((xx % 64) + 64) % 64, ((yy % 64) + 64) % 64) { continue }
                    var row = cells[yy] ?? [:]
                    row[xx] = packed
                    cells[yy] = row
                    set.insert(Pen.key(xx, yy))
                }
            }
            layerCells[layer] = set
        }
    }

    func px(_ x: Int, _ y: Int, _ col: Color) { rect(Double(x), Double(y), 1, 1, col) }

    /// One cell wide, square ends.
    func lineCells(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ col: Color) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = abs(y1 - y0)
        let sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx - dy
        while true {
            px(x, y, col)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx { err += dx; y += sy }
        }
    }

    /// Filled midpoint circle, one cell per plot.
    func circleCells(_ cx: Int, _ cy: Int, _ r: Int, _ col: Color) {
        if r <= 0 { px(cx, cy, col); return }
        var x = r, y = 0
        var err = 1 - r
        while x >= y {
            hspan(cx - x, cx + x, cy + y, col)
            hspan(cx - x, cx + x, cy - y, col)
            hspan(cx - y, cx + y, cy + x, col)
            hspan(cx - y, cx + y, cy - x, col)
            y += 1
            if err < 0 { err += 2 * y + 1 }
            else { x -= 1; err += 2 * (y - x) + 1 }
        }
    }

    private func hspan(_ x0: Int, _ x1: Int, _ y: Int, _ col: Color) {
        let a = min(x0, x1), b = max(x0, x1)
        rect(Double(a), Double(y), Double(b - a + 1), 1, col)
    }

    /// Cell-aligned 8×8 device blocks. A block may be only one color.
    func mixedBlock(cell: Int = 8) -> String? {
        if let problem { return problem }
        if scale != 1 { return "scale" }
        if rotation != 0 { return "rotation" }
        let ys = cells.keys
        let xs = cells.values.flatMap(\.keys)
        guard let minY = ys.min(), let maxY = ys.max(), let minX = xs.min(), let maxX = xs.max() else { return nil }
        let width = (maxX - minX + 1) * cell
        let height = (maxY - minY + 1) * cell
        guard let ctx = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return "bitmap" }
        ctx.setShouldAntialias(false)
        ctx.interpolationQuality = .none
        ctx.clear(CGRect(x: 0, y: 0, width: width, height: height))
        for (y, row) in cells {
            for (x, packed) in row {
                let r = CGFloat((packed >> 24) & 255) / 255
                let g = CGFloat((packed >> 16) & 255) / 255
                let b = CGFloat((packed >> 8) & 255) / 255
                let a = CGFloat(packed & 255) / 255
                ctx.setFillColor(red: r, green: g, blue: b, alpha: a)
                let rx = (x - minX) * cell
                let ry = (y - minY) * cell
                ctx.fill(CGRect(x: rx, y: ry, width: cell, height: cell))
            }
        }
        guard let data = ctx.data else { return "bitmap" }
        let bytes = data.bindMemory(to: UInt8.self, capacity: width * height * 4)
        let cols = width / cell, rows = height / cell
        for by in 0..<rows {
            for bx in 0..<cols {
                var seen: UInt32?
                for py in 0..<cell {
                    for px in 0..<cell {
                        let i = ((by * cell + py) * width + (bx * cell + px)) * 4
                        let pixel = (UInt32(bytes[i]) << 24) | (UInt32(bytes[i + 1]) << 16) | (UInt32(bytes[i + 2]) << 8) | UInt32(bytes[i + 3])
                        if let seen, seen != pixel { return "mixed" }
                        seen = pixel
                    }
                }
            }
        }
        return nil
    }

    static func pack(_ col: Color) -> UInt32 {
        let n = NSColor(col).usingColorSpace(.deviceRGB) ?? .black
        let r = UInt32((Double(n.redComponent) * 255).rounded())
        let g = UInt32((Double(n.greenComponent) * 255).rounded())
        let b = UInt32((Double(n.blueComponent) * 255).rounded())
        let a = UInt32((Double(n.alphaComponent) * 255).rounded())
        return (r << 24) | (g << 16) | (b << 8) | a
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

/// Reduce Motion, read once a second instead of on every pose.
enum MotionPreference {
    static var reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    static var checked = Date.distantPast
    static var current: Bool {
        if Date().timeIntervalSince(checked) > 1 { reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion; checked = Date() }
        return reduce
    }
}

struct Renderer {
    let m: PetModel
    var reduceMotion: Bool { MotionPreference.current }
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
            reduceMotion: reduceMotion,
            now: now, memory: m.ambientMemory(sid.isEmpty ? "solo" : sid),
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
            waving: m.waveSids.contains(sid) && now < m.waveUntil,
            turnStart: session?.turnStart.map { Date(timeIntervalSince1970: $0 / 1000) })
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

    /// 12 fps sample. Pose fields stay integers; only a drag or glide window origin may be fractional.
    func snap12(_ t: Double) -> Double {
        let q = 1.0 / 12.0
        return (t / q).rounded() * q
    }

    func cellStep(_ t: Double, _ speed: Double) -> Int {
        let s = sin(snap12(t) * speed)
        if s > 0.25 { return 1 }
        if s < -0.25 { return -1 }
        return 0
    }

    // MARK: poses
    /// Clip pose from `AnimationData` at `age` seconds into the clip (12 fps). One-shots hold their last frame.
    func pose(_ name: String, quirk: Int, local: Double, t rawT: Double, age rawAge: Double, now: Date, gaze: Double = 0) -> Pose {
        _ = quirk; _ = local; _ = now
        if reduceMotion { return Pose() }
        let t = snap12(rawT)
        _ = t; _ = gaze
        guard let data = AnimationData.clips[name], let frames = AnimationData.frames[name], !frames.isEmpty else { return Pose() }
        let loop = AnimationCatalog.index[name]?.loop ?? true
        let frame = Int((max(0, rawAge) * 12).rounded(.down))
        var p = frames[data.index(frame, loop: loop)]
        // Resting clips keep an eye on the cursor, one cell at most.
        if AnimationCatalog.ambientIds.contains(name) && p.lookX == 0 && p.lookY == 0 && p.profile == .none && p.eyes == .open {
            let cur = m.cursor()
            p.lookX = cur.x > 0.35 ? 1 : (cur.x < -0.35 ? -1 : 0)
            p.lookY = cur.y > 0.35 ? 1 : 0
        }
        return p
    }

    /// Frame index inside the current clip, for props and effects that move in whole cells.
    func clipFrame(_ name: String, age: Double) -> Int {
        let loop = AnimationCatalog.index[name]?.loop ?? true
        let raw = Int((max(0, age) * 12).rounded(.down))
        guard let data = AnimationData.clips[name] else { return raw }
        return data.index(raw, loop: loop)
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
        let bname = AnimationCatalog.resolve(name(beh))
        let slot = session?.sid ?? (m.demo.isEmpty ? "solo" : "demo")
        // Every clip starts from its first key when the character switches to it.
        if m.clipTrack[slot]?.name != bname { m.clipTrack[slot] = (bname, now) }
        let age = now.timeIntervalSince(m.clipTrack[slot]?.start ?? now)
        let gaze = session.flatMap { m.teamGaze[$0.sid] } ?? 0
        var p = pose(bname, quirk: 0, local: -1, t: t, age: age, now: now, gaze: gaze)
        let clickAge = now.timeIntervalSince(m.clickAt)
        if session?.sid == m.clickSid && clickAge < 0.4 && snap12(clickAge) < 0.25 { p.lift += 1 }
        let dropAge = now.timeIntervalSince(m.dropAt)
        if dropAge < 0.4 && snap12(dropAge) < 0.2 { p.squash = 1 }
        if bname == "sleep" && clickAge < 2.0 { p.eyes = .open; p.squash = 0 }
        if m.isGliding && session?.sid == m.glideSid { p.lean = m.vx > 8 ? 2 : (m.vx < -8 ? -2 : 0) }
        if !(m.isDragging || m.isGliding) { p = connect(slot, p, now: now) }
        return (p, now, bname, age)
    }

    /// Connector frames: between two poses every integer field moves at most one cell per 12 fps frame,
    /// so a state change walks over instead of popping. Discrete fields (eyes, profile, blush, crouch) switch at once.
    func connect(_ slot: String, _ target: Pose, now: Date) -> Pose {
        let frame = Int((now.timeIntervalSinceReferenceDate * 12).rounded(.down))
        guard let last = m.trail[slot] else { m.trail[slot] = (target, frame); return target }
        if last.frame == frame { return last.pose }
        let steps = frame - last.frame
        if steps < 0 || steps > 6 || reduceMotion {
            m.trail[slot] = (target, frame); return target
        }
        // Two sprite pixels per frame: the same speed as one old cell.
        func step(_ a: Int, _ b: Int) -> Int { a < b ? min(b, a + 2 * steps) : max(b, a - 2 * steps) }
        var p = target
        let o = last.pose
        p.lean = step(o.lean, target.lean); p.squash = step(o.squash, target.squash)
        p.lift = step(o.lift, target.lift); p.dx = step(o.dx, target.dx)
        p.armLX = step(o.armLX, target.armLX); p.armLY = step(o.armLY, target.armLY)
        p.armRX = step(o.armRX, target.armRX); p.armRY = step(o.armRY, target.armRY)
        p.lookX = step(o.lookX, target.lookX); p.lookY = step(o.lookY, target.lookY)
        p.fade = step(o.fade, target.fade)
        for i in 0..<4 { p.leg[i] = step(o.leg[i], target.leg[i]); p.legX[i] = step(o.legX[i], target.legX[i]) }
        m.trail[slot] = (p, frame)
        return p
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
        let u = max(1, m.scale.rounded())
        let fu = spritePixel(m.scale)
        let cx = anchorX ?? Double(size.width) / 2
        let ground = Double(size.height) - 14

        let sw = Double(max(8, 22 - p.lift)) * fu
        let shadow = Path(CGRect(x: (cx - sw / 2 + Double(p.dx) * fu).rounded(), y: ground.rounded(), width: max(1, sw.rounded()), height: fu))
        c.fill(shadow, with: .color(.black.opacity(0.22)), style: FillStyle(antialiased: false))

        let ox = cx - 12 * fu + Double(p.dx) * fu
        let oy = ground - 16 * fu - Double(p.lift) * fu
        let pen = Pen(c, u: fu, ox: ox, oy: oy)

        paintSprite(pen, p, bname, t, age, accent: accent)
        paintEffects(pen, bname, p, frame: clipFrame(bname, age: age), t: t, session: session, now: now)
        let headX = cx + Double(p.dx) * fu, headY = oy - Double(Renderer.overhead[bname] ?? 0) * fu
        drawBubble(&c, bname, cx: headX, headY: headY, u: u, now: now, t: t, size: size, say: say, project: project, delta: delta, session: session)
        if let subs = session?.subagentCount, subs > 1 {
            let img = m.labels.image(string: "+\(subs - 1)", size: 11, weight: .bold, color: .white)
            c.draw(Image(decorative: img, scale: 2), at: CGPoint(x: ox + 21 * u, y: ground - 4 * u), anchor: .center)
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
        let accentOn = m.displaySessions.count >= 2
        for (i, s) in list.prefix(6).enumerated() {
            var g = c
            g.translateBy(x: CGFloat(Double(i) * stride), y: 0)
            draw(&g, size: size, now: now, mood: s.mood, kind: s.kind, say: s.say, project: s.project, delta: s.delta, accent: accentOn ? sessionAccent(s.project) : nil, anchorX: anchor, session: s)
            let tag = m.oneWigglet && m.sessions.count > 1 ? "\(m.sessions.count) sessions" : m.sessionTag(s)
            drawNameTag(&g, tag, cx: anchor, size: size)
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
        var delta = delta ?? m.delta
        if delta == "+0 −0" || delta == "+0" { delta = "" }
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
        // Fit the panel: a lone Wigglet's panel is narrow, so shorten rather than clip at the edge.
        let room = Double(size.width) - 30
        while text.count > 4 && m.labels.width(string: text, size: 12, weight: .semibold) > room { text = String(text.dropLast(2)) + "…" }
        while sub.count > 4 && m.labels.width(string: sub, size: 10, weight: .medium) > room { sub = String(sub.dropLast(2)) + "…" }
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

/// Walks every catalog clip at 12 fps through a recording pen and an 8-point cell raster.
func runPixelAudit() -> Int32 {
    let renderer = Renderer(m: PetModel())
    var failed = false
    for anim in AnimationCatalog.all {
        let steps = max(1, Int((anim.duration * 12).rounded(.up)))
        var bad = ""
        for i in 0..<steps {
            let t = Double(i) / 12.0
            let pose = renderer.pose(anim.id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
            let pen = Pen(recordingU: 8)
            renderer.paintSprite(pen, pose, anim.id, t, t)
            if let problem = pen.mixedBlock() {
                bad = problem
                break
            }
        }
        if bad.isEmpty { print("\(anim.id) \(steps) PASS") }
        else { print("\(anim.id) \(steps) FAIL \(bad)"); failed = true }
    }
    return failed ? 1 : 0
}

/// Frame audit. For every clip, walks each 12 fps frame (in-betweens included) and fails on:
///  (a) adjacent frames whose shape differs by more than `maxDelta` pixels (lift, dx, lean and body drop are translation: max 2),
///  (b) a loop seam that breaks the same rules,
///  (c) a carried prop (clip `held`) more than 2 pixels from a hand,
///  (d) an arm or leg that is not connected to the body (unless the clip is `airborne`).
/// A frame that starts a `cut` key may jump.
func runFrameAudit() -> Int32 {
    let renderer = Renderer(m: PetModel())
    var failed = false
    func frameCells(_ id: String, _ pose: Pose, _ f: Int) -> Pen {
        let pen = Pen(recordingU: 1)
        let age = Double(f) / 12
        renderer.paintSprite(pen, pose, id, age, age)
        return pen
    }
    func flat(_ pen: Pen) -> [Int: UInt32] {
        var out: [Int: UInt32] = [:]
        for (y, row) in pen.cells { for (x, c) in row { out[Pen.key(x, y)] = c } }
        return out
    }
    func xy(_ k: Int) -> (Int, Int) { (k % 4096 - 2048, k / 4096 - 512) }
    func changed(_ a: [Int: UInt32], _ b: [Int: UInt32], dx: Int = 0, dy: Int = 0) -> Int {
        var moved: [Int: UInt32] = [:]
        for (k, c) in a { let p = xy(k); moved[Pen.key(p.0 + dx, p.1 + dy)] = c }
        var n = 0
        for k in Set(moved.keys).union(b.keys) where moved[k] != b[k] { n += 1 }
        return n
    }
    func near(_ a: Set<Int>, _ b: Set<Int>, reach: Int) -> Bool {
        for k in a {
            let (x, y) = xy(k)
            for dy in -reach...reach { for dx in -reach...reach where b.contains(Pen.key(x + dx, y + dy)) { return true } }
        }
        return false
    }
    /// Each connected group of `cells` must touch `anchor`.
    func allAttached(_ cells: Set<Int>, to anchor: Set<Int>) -> Bool {
        var left = cells
        while let seed = left.first {
            var group: Set<Int> = [seed], queue = [seed]
            left.remove(seed)
            while let k = queue.popLast() {
                let (x, y) = xy(k)
                for (dx, dy) in [(1, 0), (-1, 0), (0, 1), (0, -1)] {
                    let n = Pen.key(x + dx, y + dy)
                    if left.contains(n) { left.remove(n); group.insert(n); queue.append(n) }
                }
            }
            if !near(group, anchor, reach: 1) { return false }
        }
        return true
    }
    for anim in AnimationCatalog.all {
        guard let data = AnimationData.clips[anim.id], let frames = AnimationData.frames[anim.id] else {
            print("\(anim.id) FAIL no frame data"); failed = true; continue
        }
        let n = frames.count, cuts = data.cutFrames
        var problems: [String] = []
        typealias Shot = (cells: [Int: UInt32], pose: Pose)
        var prev: Shot?, first: Shot?
        func compare(_ a: Shot, _ b: Shot, at f: Int, what: String) {
            let mx = Frame(b.pose).bx - Frame(a.pose).bx, my = Frame(b.pose).top - Frame(a.pose).top
            let d = min(changed(a.cells, b.cells), changed(a.cells, b.cells, dx: mx, dy: my))
            if d > data.maxDelta + (data.airborne ? 40 : 0) { problems.append("\(what) \(f): \(d) px") }
            let liftStep = data.airborne ? 4 : 2
            if abs(a.pose.lift - b.pose.lift) > liftStep || abs(a.pose.dx - b.pose.dx) > 2 || abs(mx) > 2 || abs(my) > 2 {
                problems.append("\(what) \(f): jumps more than 2 px")
            }
        }
        for f in 0..<n {
            let pose = frames[f]
            let pen = frameCells(anim.id, pose, f)
            let cur: Shot = (flat(pen), pose)
            if let prev, !cuts.contains(f) { compare(prev, cur, at: f, what: "pop") }
            if first == nil { first = cur }
            prev = cur
            let body = pen.layerCells[.body] ?? []
            if data.held {
                let prop = pen.layerCells[.prop] ?? [], arms = pen.layerCells[.arm] ?? []
                if prop.isEmpty { problems.append("frame \(f): held prop missing") }
                else if !near(prop, arms, reach: 2) { problems.append("frame \(f): prop floats off the hand") }
            }
            if !data.airborne && pose.fade == 0 {
                if !allAttached(pen.layerCells[.arm] ?? [], to: body) { problems.append("frame \(f): arm detached") }
                if !allAttached(pen.layerCells[.leg] ?? [], to: body) { problems.append("frame \(f): leg detached") }
            }
        }
        if anim.loop, data.loops, let prev, let first, n > 1, !cuts.contains(0) { compare(prev, first, at: n, what: "seam") }
        if problems.isEmpty { print("\(anim.id) \(n) PASS") }
        else { print("\(anim.id) \(n) FAIL " + problems.prefix(3).joined(separator: "; ")); failed = true }
    }
    return failed ? 1 : 0
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
        .frame(width: CGFloat(teamPanelWidth(count: model.displaySessions.count, scale: model.scale)), height: canvasH)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(model.demo.isEmpty ? model.accessLabel : model.demo[Int(clock.now.timeIntervalSinceReferenceDate / 4) % model.demo.count])
    }
}
