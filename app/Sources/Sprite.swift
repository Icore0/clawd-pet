import AppKit
import SwiftUI

// Clawd's proportions come from the official pixel mascot:
// body 8x6 units, arm nubs 2x2, 1x1 eyes at body cols 1 and 6, four 1-wide legs at cols 0,2,5,7.
// Sprite space: X 0..12 (arms+body+arms), Y 0..8 (body 0..6, legs 6..8).

let clawdOrange = Color(red: 0.851, green: 0.467, blue: 0.341)   // #D97757
let clawdDark = Color(red: 0.745, green: 0.408, blue: 0.294)     // #BE684B
let ink = Color.black

enum Eyes: Equatable { case open, tall, dash, cross }
enum Profile: Equatable { case none, left, right }

/// Whole cells only. `lean` shifts the upper body one cell. `squash` drops one body row and shortens the legs one cell.
struct Pose: Equatable {
    var lean = 0
    var squash = 0
    var lift = 0
    var dx = 0
    var armLX = 0, armLY = 0
    var armRX = 0, armRY = 0
    var eyes = Eyes.open
    var lookX = 0, lookY = 0
    var leg = [0, 0, 0, 0]
    var legX = [0, 0, 0, 0]
    var blush = false
    var profile = Profile.none
}

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

    init(_ c: GraphicsContext, u: Double, ox: Double, oy: Double) {
        self.c = c
        self.u = max(1, u.rounded())
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
        let path = Path(CGRect(x: px0, y: py0, width: pw, height: ph))
        c?.fill(path, with: .color(col), style: FillStyle(antialiased: false))
        if recording {
            let packed = Pen.pack(col)
            for yy in iy..<(iy + ih) {
                for xx in ix..<(ix + iw) {
                    var row = cells[yy] ?? [:]
                    row[xx] = packed
                    cells[yy] = row
                }
            }
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

func drawClawd(_ p: Pen, _ pose: Pose, color: Color = clawdOrange, eyes: Bool = true, arms: Bool = true, accent: Color? = nil) {
    let lean = max(-1, min(1, pose.lean))
    let squash = pose.squash == 0 ? 0 : 1
    let bodyH = 6 - squash
    let legH = max(1, 2 - squash)
    let bodyX = 2 + lean
    p.rect(Double(bodyX), 0, 8, Double(bodyH), color)
    if pose.profile == .left { p.rect(Double(bodyX), 0, 1, Double(bodyH), clawdDark) }
    if pose.profile == .right { p.rect(Double(bodyX + 7), 0, 1, Double(bodyH), clawdDark) }
    if let accent, bodyH > 4 { p.rect(Double(bodyX), 4, 8, 1, accent) }
    let cols = [0, 2, 5, 7]
    for i in 0..<4 {
        let h = max(1, legH - pose.leg[i])
        p.rect(Double(bodyX + cols[i] + pose.legX[i]), Double(bodyH), 1, Double(h), color)
    }
    if arms {
        p.rect(Double(lean + pose.armLX), Double(2 + pose.armLY), 2, 2, color)
        p.rect(Double(10 + lean - pose.armRX), Double(2 + pose.armRY), 2, 2, color)
    }
    guard eyes else { return }
    let eyeXs: [Int]
    switch pose.profile {
    case .none: eyeXs = [bodyX + 1, bodyX + 6]
    case .left: eyeXs = [bodyX + 5]
    case .right: eyeXs = [bodyX + 2]
    }
    for ex in eyeXs {
        let x = ex + pose.lookX
        let y = 1 + pose.lookY
        switch pose.eyes {
        case .open: p.rect(Double(x), Double(y), 1, 1, ink)
        case .tall: p.rect(Double(x), Double(y), 1, 2, ink)
        case .dash: p.rect(Double(x), Double(y + 1), 1, 1, ink)
        case .cross:
            for (i, j) in [(0, 0), (2, 0), (1, 1), (0, 2), (2, 2)] {
                p.rect(Double(x + i), Double(y + j), 1, 1, ink)
            }
        }
    }
    if pose.blush {
        p.rect(Double(bodyX), 3, 1, 1, Color.pink)
        p.rect(Double(bodyX + 7), 3, 1, 1, Color.pink)
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

    func heldPose(_ name: String, _ t: Double) -> Pose? {
        let frames: [Pose]
        switch name {
        case "breathe":
            frames = [Pose(), Pose(lift: 1)]
        case "blink":
            frames = [Pose(eyes: .dash), Pose(), Pose(), Pose()]
        case "glance":
            frames = [Pose(lookX: 1, profile: .right), Pose(), Pose(lookX: -1, profile: .left), Pose()]
        case "sleep":
            frames = [Pose(armLY: 1, armRY: 1, eyes: .dash), Pose(squash: 1, armLY: 1, armRY: 1, eyes: .dash)]
        case "hello":
            frames = [Pose(lift: 1, armRY: -2), Pose(armRY: -2), Pose(lift: 1, armRY: -1)]
        case "bye":
            frames = [Pose(armRY: -2), Pose(armRY: -1, eyes: .dash), Pose(armRY: -2, eyes: .dash)]
        case "done":
            frames = [Pose(lift: 2, armLY: -2, armRY: -2, blush: true), Pose(lift: 1, armLY: -2, armRY: -2, blush: true), Pose(blush: true)]
        case "oops":
            frames = [Pose(dx: -1, armLY: 1, armRY: 1, eyes: .cross), Pose(dx: 1, armLY: 1, armRY: 1, eyes: .cross), Pose(eyes: .cross)]
        case "ask":
            frames = [Pose(lift: 1, armRY: -2, eyes: .tall), Pose(lean: 1, armRY: -2, eyes: .tall), Pose(armRY: -1, eyes: .tall)]
        case "yourTurn":
            frames = [Pose(lean: 1, armLX: 1, armLY: 1, armRX: 1, armRY: 1), Pose(lean: 1, armLX: 2, armRX: 2, leg: [0, 0, 1, 0])]
        case "drag":
            frames = [
                Pose(lift: 1, armLY: -2, armRY: -1, eyes: .tall, leg: [-1, -1, -1, -1]),
                Pose(lean: 1, lift: 1, armLY: -1, armRY: -2, eyes: .tall, leg: [-1, 0, -1, 0]),
                Pose(lean: -1, lift: 1, armLY: -2, armRY: -2, eyes: .tall, leg: [0, -1, 0, -1])
            ]
        case "pet":
            frames = [Pose(lean: 1, blush: true), Pose(lean: -1, eyes: .dash, blush: true), Pose(blush: true)]
        case "read":
            frames = [
                Pose(armLX: 1, armLY: 1, armRX: 1, armRY: 1, lookX: -1, lookY: 1),
                Pose(armLX: 1, armLY: 1, armRX: 1, armRY: 1, lookX: 1, lookY: 1),
                Pose(armLX: 2, armLY: 1, armRX: 2, armRY: 1, lookY: 1)
            ]
        case "edit":
            frames = [Pose(armLX: 1, armLY: 2, armRX: 1, armRY: 1, lookY: 1), Pose(armLX: 1, armLY: 1, armRX: 1, armRY: 2, lookY: 1)]
        case "bash":
            frames = [Pose(armLX: 1, armLY: 2, armRX: 1, armRY: 1, lookY: 1), Pose(armLX: 1, armLY: 1, armRX: 1, armRY: 2, eyes: .dash, lookY: 1)]
        case "search":
            frames = [Pose(armRX: -1, armRY: 1, lookX: -1, profile: .left), Pose(armRX: 1, armRY: 1, lookX: 1, profile: .right), Pose(armRY: 1, lookX: 1)]
        case "build":
            frames = [Pose(armRY: 1, lookY: 1), Pose(lift: 1, armRY: 0, eyes: .dash, lookY: 1), Pose(lean: 1, armRY: 1, lookY: 1)]
        default:
            return nil
        }
        let hold = name == "breathe" ? 1.5 : (2.0 / 12.0)
        let count = frames.count
        let i = Int(floor(t / hold)) % count
        return frames[(i + count) % count]
    }

    // MARK: poses
    func pose(_ name: String, quirk: Int, local: Double, t rawT: Double, age rawAge: Double, now: Date, gaze: Double = 0) -> Pose {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion { return Pose() }
        let t = snap12(rawT)
        let age = snap12(rawAge)
        let placed = AnimationCatalog.placement(id: name, elapsed: age)
        let phase = placed?.track.phase ?? "action"
        if phase != "action" {
            var wind = Pose()
            if placed?.track.pose == "squash" { wind.squash = 1 }
            else if placed?.track.pose == "settle" {
                let dur = placed?.track.duration ?? 0
                let loc = placed?.local ?? 0
                if loc < dur / 2 { wind.lift = 1 }
            }
            return wind
        }
        if let held = heldPose(name, t) { return held }
        var p = Pose()
        if t.truncatingRemainder(dividingBy: 4.25) < (1.0 / 12.0) { p.eyes = .dash }
        let cur = m.cursor()
        p.lookX = cur.x > 0.35 ? 1 : (cur.x < -0.35 ? -1 : 0)
        p.lookY = cur.y > 0.35 ? 1 : 0
        let beat = cellStep(t, 14)
        switch name {
        case "idle":
            if local >= 0 {
                let q = snap12(local)
                switch quirk {
                case 2:
                    p.lookX = cellStep(q, 2.2)
                    p.lean = p.lookX
                case 3:
                    if cellStep(q, 1) > 0 { p.armLY = -2; p.armRY = -2; p.eyes = .dash }
                case 4:
                    p.eyes = .dash
                    p.armRY = cellStep(q, 1) > 0 ? -1 : 0
                case 5:
                    p.lift = abs(cellStep(q, 7))
                    p.armLY = -1; p.armRY = -1
                case 6:
                    p.leg[0] = max(0, cellStep(q, 14))
                    p.leg[3] = max(0, cellStep(q, 14))
                    p.lookY = 1
                case 7:
                    p.lean = cellStep(q, 8)
                    p.armLY = cellStep(q, 8)
                    p.armRY = -p.armLY
                case 8:
                    p.lift = abs(cellStep(q, 6))
                    p.armLY = cellStep(q, 6)
                    p.armRY = -p.armLY
                default: break
                }
            }
        case "think":
            p.eyes = .tall
            p.lookX = cellStep(t, 1.5)
            p.lean = p.lookX
            p.armRX = -1
            p.armRY = 1
            p.lift = cellStep(t, 3) > 0 ? 1 : 0
        case "web":
            p.armLX = 1; p.armRX = 1; p.armLY = 2; p.armRY = 2
            p.lookY = 1
            p.lift = cellStep(t, 4) > 0 ? 1 : 0
        case "agent":
            p.armLY = cellStep(t, 5) > 0 ? -2 : -1
            p.armRY = cellStep(t, 5) > 0 ? -1 : -2
            p.leg[1] = max(0, beat)
            p.leg[2] = max(0, -beat)
        case "test":
            p.armRX = 1; p.armRY = 2; p.lookX = 1; p.lookY = 1
            p.lift = cellStep(t, 5) > 0 ? 1 : 0
        case "git":
            p.armRY = cellStep(t, 3) > 0 ? -1 : -2
            p.lookX = 1
            p.lean = cellStep(t, 2)
        case "install":
            p.armLY = -2; p.armRY = -2; p.eyes = .tall
            if cellStep(t, 7.5) > 0 { p.squash = 1 }
        case "plan":
            p.armLX = 1; p.armRX = 1; p.armLY = 1; p.armRY = 1
            p.lookX = cellStep(t, 2)
            p.lookY = 1
        case "compact":
            p.squash = cellStep(t, 3) == 0 ? 1 : 0
            p.eyes = .dash
            p.armLY = -1; p.armRY = -1
        case "listen":
            p.armLY = -1; p.armRY = -1; p.eyes = .tall
            p.lean = cellStep(t, 2)
            p.lift = cellStep(t, 6) > 0 ? 1 : 0
        case "chatThink":
            p.eyes = .tall
            p.lookX = cellStep(t, 2.3)
            p.lean = cellStep(t, 1.7)
            p.armRX = -1; p.armRY = 1
            p.leg[0] = max(0, beat)
            p.leg[3] = max(0, -beat)
        case "chatTalk":
            p.lift = cellStep(t, 8) > 0 ? 1 : 0
            p.armLY = cellStep(t, 7)
            p.armRY = cellStep(t, 7)
            p.eyes = Int(t * 2) % 3 == 0 ? .dash : .open
        case "glide":
            p.lean = m.vx > 8 ? 1 : (m.vx < -8 ? -1 : 0)
            p.eyes = .cross
            p.armLY = cellStep(t, 20)
            p.armRY = -p.armLY
            p.lift = 1
        case "conflictStare":
            p.lookX = gaze >= 0 ? 1 : -1
            p.profile = gaze >= 0 ? .right : .left
            p.eyes = .dash
            p.lean = p.lookX
        case "highFive", "wave", "hop":
            p.armRY = cellStep(t, 10) > 0 ? -2 : -1
            p.lift = cellStep(t, 6) > 0 ? 1 : 0
        case "parcel":
            p.armLX = 1; p.armLY = 1; p.armRY = -1
        case "nap":
            p.eyes = .dash; p.squash = 1; p.armLY = 1; p.armRY = 1
        case "bump":
            p.dx = cellStep(t, 18)
            p.squash = 1
        case "poke":
            p.squash = 1; p.eyes = .dash
        case "spin":
            p.lean = cellStep(t, 14)
        case "dizzy":
            p.eyes = .cross
            p.lean = cellStep(t, 12)
        case "lean":
            p.lean = 1
            p.lookX = 1
        case "peek":
            p.lookX = 1
            p.profile = .right
            p.eyes = .dash
        case "opening", "listening", "reading":
            p.eyes = .tall
            p.lean = 1
        case "thinking":
            p.eyes = .tall
            p.armRX = -1; p.armRY = 1
        case "talking":
            p.armLY = cellStep(t, 7)
            p.armRY = cellStep(t, 7)
        case "offline", "outOfCredits", "rateLimited", "unauthorized", "timeout":
            p.eyes = .dash
            p.squash = 1
        case "stretch":
            if cellStep(t, 1.5) > 0 { p.armLY = -2; p.armRY = -2; p.lift = 1 }
        case "yawn":
            p.eyes = .dash
            p.lift = cellStep(t, 1.2) > 0 ? 1 : 0
            p.armLY = 1; p.armRY = 1
        case "dance":
            let up = cellStep(t, 5) > 0
            p.armLY = up ? -2 : 1
            p.armRY = up ? 1 : -2
        case "hum":
            p.lift = cellStep(t, 10) > 0 ? 1 : 0
        case "mote":
            p.lookX = cellStep(t, 1.6)
            p.armRY = cellStep(t, 1.6) > 0 ? -1 : 0
        case "juggle":
            let wave = cellStep(t, 6)
            p.armLY = wave > 0 ? -1 : 0
            p.armRY = wave < 0 ? -1 : 0
        case "dream":
            p.eyes = .dash
            p.squash = cellStep(t, 1.1) > 0 ? 1 : 0
            p.armLY = 1; p.armRY = 1
            p.lookX = 0; p.lookY = 0
        default: break
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
        if session?.sid == m.clickSid && clickAge < 0.4 && snap12(clickAge) < 0.25 { p.lift += 1 }
        let dropAge = now.timeIntervalSince(m.dropAt)
        if dropAge < 0.4 && snap12(dropAge) < 0.2 { p.squash = 1 }
        if bname == "sleep" && clickAge < 2.0 { p.eyes = .open; p.squash = 0 }
        if mood == "waiting" && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion && cellStep(t, 4) != 0 {
            p.lift = min(2, p.lift + 1)
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
        let u = max(1, m.scale.rounded())
        let cx = anchorX ?? Double(size.width) / 2
        let ground = Double(size.height) - 14

        let sw = Double(max(4, 11 - p.lift)) * u
        let shadow = Path(CGRect(x: (cx - sw / 2 + Double(p.dx) * u).rounded(), y: ground.rounded(), width: max(1, sw.rounded()), height: u))
        c.fill(shadow, with: .color(.black.opacity(0.22)), style: FillStyle(antialiased: false))

        let ox = cx - 6 * u + Double(p.dx) * u
        let oy = ground - 8 * u - Double(p.lift) * u
        let pen = Pen(c, u: u, ox: ox, oy: oy)

        let isTyping = bname == "edit" || bname == "bash"
        if isTyping { drawClawd(pen, p, arms: false, accent: accent); drawLaptop(pen, bname, t); drawArms(pen, p) }
        else {
            drawClawd(pen, p, accent: accent)
            drawProp(pen, bname, p, t, front: true)
        }

        drawHat(pen, bname, t, age)
        let headX = cx + Double(p.dx) * u, headY = oy
        drawEffects(&c, bname, t: t, age: age, cx: headX, headY: headY, ground: ground, u: u, pen: pen, p: p, now: now)
        drawBubble(&c, bname, cx: headX, headY: headY, u: u, now: now, t: t, size: size, say: say, project: project, delta: delta, session: session)
        let subs = session?.subagentCount ?? 0
        if subs > 0 {
            let shown = min(4, subs)
            for i in 0..<shown {
                let mu = max(1, (u * 0.35).rounded())
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
        let lean = max(-1, min(1, p.lean))
        pen.rect(Double(lean + p.armLX), Double(2 + p.armLY), 2, 2, clawdOrange)
        pen.rect(Double(10 + lean - p.armRX), Double(2 + p.armRY), 2, 2, clawdOrange)
    }

    // MARK: props
    func drawLaptop(_ p: Pen, _ kind: String, _ t: Double) {
        let screen = Color(red: 0.11, green: 0.11, blue: 0.13), edge = Color(red: 0.32, green: 0.32, blue: 0.36)
        p.rect(3, 3, 7, 3, edge)
        p.rect(3, 4, 6, 2, screen)
        p.rect(2, 6, 8, 1, Color(red: 0.42, green: 0.42, blue: 0.46))
        let frame = Int(snap12(t) * 12)
        let rows = [4, 5]
        for (i, y) in rows.enumerated() {
            let len = 1 + ((i + frame) % 4)
            if kind == "bash" {
                p.px(3, y, .green)
                p.rect(4, Double(y), Double(len), 1, Color.green.opacity(0.75))
            } else {
                p.rect(3 + Double(i % 2), Double(y), Double(len), 1, i % 2 == 0 ? clawdOrange : Color.white.opacity(0.8))
            }
        }
        if kind == "bash" && frame % 12 < 6 { p.px(3, 5, .white) }
    }

    func paintSprite(_ pen: Pen, _ pose: Pose, _ name: String, _ t: Double, _ age: Double) {
        let typing = name == "edit" || name == "bash"
        if typing {
            drawClawd(pen, pose, arms: false)
            drawLaptop(pen, name, t)
            drawArms(pen, pose)
        } else {
            drawClawd(pen, pose)
            drawProp(pen, name, pose, t, front: true)
        }
        drawHat(pen, name, t, age)
    }

    func drawProp(_ p: Pen, _ kind: String, _ pose: Pose, _ t: Double, front: Bool) {
        switch kind {
        case "read", "burstRead":
            p.rect(3, 3, 6, 4, Color.white.opacity(0.95))
            p.rect(6, 3, 1, 4, Color.gray.opacity(0.6))
            let flip = Int(snap12(t) * (kind == "burstRead" ? 6 : 2)) % 2
            for i in 0..<3 {
                let y = 4 + i
                p.rect(3, Double(y), Double(flip == 0 ? 2 : 1), 1, Color.gray.opacity(0.6))
                p.rect(7, Double(y), Double(flip == 0 ? 1 : 2), 1, Color.gray.opacity(0.6))
            }
            drawArms(p, pose)
        case "plan":
            p.rect(4, 3, 5, 4, Color(red: 0.55, green: 0.38, blue: 0.22))
            p.rect(4, 3, 4, 3, Color.white.opacity(0.95))
            p.rect(5, 2, 2, 1, Color.gray)
            let n = Int(snap12(t) * 2) % 4
            for i in 0..<3 {
                let y = 3 + i
                p.px(4, y, i < n ? Color.green : Color.gray.opacity(0.4))
                p.rect(5, Double(y), 2, 1, Color.gray.opacity(0.6))
            }
            drawArms(p, pose)
        case "search":
            let lx = 6 + cellStep(t, 2.2) * 2
            drawArms(p, pose)
            p.lineCells(lx + 1, 5, lx + 2, 6, Color(red: 0.4, green: 0.3, blue: 0.2))
            p.circleCells(lx, 4, 2, Color(white: 0.85))
            p.circleCells(lx, 4, 1, Color.cyan.opacity(0.25))
        case "web":
            drawArms(p, pose)
            p.circleCells(6, 5, 2, Color.white.opacity(0.8))
            p.circleCells(6, 5, 1, Color(red: 0.2, green: 0.5, blue: 0.9))
            let hop = Int(snap12(t) * 4) % 3
            p.px(5 + hop, 4, Color(red: 0.3, green: 0.75, blue: 0.4))
        case "test":
            drawArms(p, pose)
            let liquid = [Color.green, Color.purple, Color.cyan][Int(snap12(t) / 2) % 3]
            p.rect(9, 3, 1, 1, Color.white.opacity(0.75))
            p.lineCells(8, 4, 11, 6, Color.white.opacity(0.45))
            p.lineCells(11, 6, 7, 6, Color.white.opacity(0.45))
            p.rect(8, 5, 3, 2, liquid.opacity(0.85))
            p.px(9, 4, Color.white.opacity(0.9))
        case "build":
            drawArms(p, pose)
            let swing = cellStep(t, 10)
            let wood = Color(red: 0.55, green: 0.38, blue: 0.22)
            p.lineCells(11, 3 + pose.armRY, 12 + swing, 1, wood)
            p.lineCells(11 + swing, 1, 13 + swing, 2, Color(white: 0.45))
        case "git":
            drawArms(p, pose)
            p.lineCells(13, 0, 13, 6, Color.white.opacity(0.7))
            p.lineCells(13, 3, 15, 2, Color.white.opacity(0.7))
            let on = Int(snap12(t) * 2) % 4
            let nodes = [(13, 0), (13, 3), (13, 6), (15, 2)]
            for (i, n) in nodes.enumerated() {
                p.circleCells(n.0, n.1, 1, on == i ? Color.orange : Color.white.opacity(0.85))
            }
        case "install":
            drawArms(p, pose)
            let by = -5 + (Int(snap12(t) * 4) % 6)
            p.rect(4, Double(by), 3, 2, Color(red: 0.75, green: 0.55, blue: 0.32))
            p.rect(6, Double(by), 1, 2, Color(red: 0.9, green: 0.8, blue: 0.55))
        case "deploy":
            drawArms(p, pose)
            p.px(6, 1, Color.white.opacity(0.9))
            p.lineCells(5, 2, 7, 2, Color.white.opacity(0.9))
            p.lineCells(4, 3, 8, 3, Color.white.opacity(0.9))
        case "commit":
            drawArms(p, pose)
            p.circleCells(9, 2, 1, Color(red: 0.75, green: 0.15, blue: 0.18))
            p.px(9, 2, Color.white.opacity(0.85))
        case "push":
            drawArms(p, pose)
            p.lineCells(8, 3, 11, 2, Color(red: 0.35, green: 0.6, blue: 0.9))
            p.px(11, 1, Color(red: 0.35, green: 0.6, blue: 0.9))
            p.px(10, 3, Color(red: 0.35, green: 0.6, blue: 0.9))
        case "pull":
            drawArms(p, pose)
            p.rect(8, 2, 2, 2, Color(red: 0.55, green: 0.38, blue: 0.22))
        case "lint":
            drawArms(p, pose)
            p.lineCells(8, 1, 11, 4, Color(red: 0.85, green: 0.55, blue: 0.7))
        case "migrate":
            drawArms(p, pose)
            p.rect(8, 3, 2, 1, Color(red: 0.45, green: 0.55, blue: 0.75))
            p.rect(9, 2, 2, 1, Color(red: 0.55, green: 0.65, blue: 0.85))
            p.rect(9, 1, 2, 1, Color(red: 0.65, green: 0.75, blue: 0.9))
        case "docker":
            drawArms(p, pose)
            p.rect(8, 2, 3, 2, Color(red: 0.2, green: 0.55, blue: 0.85))
        case "serve":
            drawArms(p, pose)
            p.rect(9, 2, 2, 2, Color(red: 0.9, green: 0.7, blue: 0.3))
            p.px(9, 1, Color.yellow.opacity(0.9))
        case "mcp":
            drawArms(p, pose)
            p.lineCells(8, 2, 11, 2, .white)
        case "notebook":
            drawArms(p, pose)
            p.rect(3, 3, 6, 3, Color.white.opacity(0.95))
        case "webSearch":
            drawArms(p, pose)
            p.circleCells(9, 2, 1, .white)
            p.px(9, 2, Color.cyan.opacity(0.35))
        case "webFetch":
            drawArms(p, pose)
            p.rect(8, 1, 3, 3, Color.white.opacity(0.92))
            p.rect(8, 2, 2, 1, Color.gray.opacity(0.6))
        case "bandage":
            drawArms(p, pose)
            p.rect(3, 2, 6, 1, Color.white.opacity(0.9))
        case "sweat":
            drawArms(p, pose)
            p.px(9, 1, Color.cyan.opacity(0.85))
        case "tea", "coffee":
            drawArms(p, pose)
            p.rect(8, 2, 2, 2, kind == "coffee" ? Color(red: 0.45, green: 0.28, blue: 0.16) : Color(red: 0.7, green: 0.85, blue: 0.75))
            p.rect(10, 3, 1, 1, .white.opacity(0.8))
        case "book":
            drawArms(p, pose)
            p.rect(8, 2, 3, 3, Color(red: 0.35, green: 0.45, blue: 0.7))
        case "frantic":
            drawArms(p, pose)
            p.lineCells(12, 1, 14, 2, .white.opacity(0.8))
            p.lineCells(12, 2, 15, 3, .white.opacity(0.7))
            p.lineCells(12, 4, 14, 4, .white.opacity(0.6))
        case "watch":
            drawArms(p, pose)
            p.circleCells(9, 2, 1, .white)
        case "flag":
            drawArms(p, pose)
            p.lineCells(9, 1, 9, 4, .white)
            p.rect(9, 1, 2, 1, Color.orange)
        case "nightcap":
            drawArms(p, pose)
            p.circleCells(10, 1, 1, Color(white: 0.92))
            p.px(10, 1, Color(red: 0.12, green: 0.12, blue: 0.16))
        case "conflict":
            drawArms(p, pose)
            p.lineCells(8, 1, 11, 4, Color.red)
            p.lineCells(11, 1, 8, 4, Color.red)
        default:
            drawArms(p, pose)
        }
        _ = front
    }

    func drawHat(_ p: Pen, _ b: String, _ t: Double, _ age: Double) {
        let dark = Color(white: 0.16)
        _ = t
        switch b {
        case "read":
            for ex in [3, 8] {
                p.rect(Double(ex), 1, 2, 1, .white)
                p.rect(Double(ex), 2, 1, 1, .white)
                p.rect(Double(ex + 1), 2, 1, 1, .white)
            }
            p.rect(5, 1, 3, 1, .white)
        case "edit":
            p.rect(3, -1, 7, 1, dark)
            p.rect(2, 1, 1, 2, dark)
            p.rect(9, 1, 1, 2, dark)
            p.px(2, 1, clawdOrange)
            p.px(9, 2, clawdOrange)
        case "bash":
            p.rect(2, -1, 7, 2, dark)
            p.rect(2, 0, 7, 1, Color(white: 0.28))
            p.rect(5, -2, 2, 1, dark)
            p.px(3, -1, Color.green)
        case "search":
            p.rect(2, 0, 8, 1, Color(red: 0.45, green: 0.3, blue: 0.18))
            p.rect(3, -2, 6, 2, Color(red: 0.55, green: 0.38, blue: 0.22))
            p.rect(3, -1, 6, 1, Color(red: 0.3, green: 0.2, blue: 0.12))
        case "web":
            p.rect(2, 0, 9, 1, Color(red: 0.85, green: 0.72, blue: 0.45))
            p.rect(3, -2, 6, 2, Color(red: 0.9, green: 0.78, blue: 0.5))
            p.rect(3, -1, 6, 1, Color(red: 0.7, green: 0.2, blue: 0.2))
        case "agent":
            let gold = Color(red: 0.98, green: 0.8, blue: 0.2)
            p.rect(3, -1, 6, 1, gold)
            for x in [3, 5, 8] { p.rect(Double(x), -2, 1, 1, gold) }
            p.px(6, -1, Color.red)
        case "build":
            let y = Color(red: 0.98, green: 0.78, blue: 0.1)
            p.rect(3, -2, 7, 2, y)
            p.rect(2, 0, 8, 1, y)
            p.rect(5, -2, 1, 1, y)
        case "test":
            p.rect(3, 1, 2, 2, Color.cyan.opacity(0.35))
            p.rect(7, 1, 2, 2, Color.cyan.opacity(0.35))
            p.rect(3, 1, 6, 1, Color(white: 0.9))
        case "plan":
            p.rect(9, -1, 1, 2, Color.yellow)
            p.px(9, -1, Color.pink)
        case "sleep":
            p.rect(3, -1, 5, 1, Color(red: 0.75, green: 0.2, blue: 0.2))
            p.rect(7, -2, 2, 2, Color(red: 0.75, green: 0.2, blue: 0.2))
            p.px(10, 1, .white)
            p.rect(3, 0, 6, 1, .white)
        case "oops":
            p.rect(6, 0, 3, 1, Color(red: 0.92, green: 0.8, blue: 0.62))
            p.px(7, 0, Color(white: 0.5))
        case "install":
            p.rect(3, -1, 6, 1, Color(red: 0.2, green: 0.4, blue: 0.7))
            p.rect(3, 0, 8, 1, Color(red: 0.2, green: 0.4, blue: 0.7))
        case "done":
            if age > 0.5 {
                let y = age > 0.85 ? 1.0 : -2.0
                p.rect(3, y, 3, 2, ink)
                p.rect(6, y, 3, 2, ink)
                p.px(3, Int(y), Color.white.opacity(0.6))
                p.px(7, Int(y), Color.white.opacity(0.6))
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
                let x = (cx + cos(a) * 7 * u).rounded()
                let y = (headY + 2 * u + sin(a) * 3 * u).rounded()
                c.fill(Path(CGRect(x: x, y: y, width: u, height: u)), with: .color(confetti[i % 6].opacity(0.9)), style: FillStyle(antialiased: false))
            }
        case "edit", "bash", "read", "plan", "search":
            for i in 0..<3 {
                let a = t * 2.4 + Double(i) * 2.094
                let x = (cx + cos(a) * 8 * u).rounded()
                let y = (headY + 3 * u + sin(a) * 2.6 * u).rounded()
                c.fill(Path(CGRect(x: x, y: y, width: u, height: u)), with: .color(confetti[(i * 2) % 6].opacity(0.85)), style: FillStyle(antialiased: false))
            }
        case "web":
            for i in 0..<3 {
                let k = (t * 0.9 + Double(i) / 3).truncatingRemainder(dividingBy: 1)
                c.stroke(Path { $0.addArc(center: CGPoint(x: cx, y: headY - 0.2 * u), radius: (1.5 + k * 3) * u, startAngle: .degrees(225), endAngle: .degrees(315), clockwise: false) },
                         with: .color(.cyan.opacity(0.9 * (1 - k))), lineWidth: 0.35 * u)
            }
        case "agent":
            for (i, side) in [-1.0, 1.0].enumerated() {
                let mu = max(1, (u * 0.3).rounded())
                let hop = abs(sin(t * 6 + Double(i) * 2)) * 1.5
                let mp = Pen(c, u: mu, ox: cx + side * 9.5 * u - 6 * mu, oy: ground - 8 * mu - hop * mu * 2)
                var mpose = Pose(); mpose.armLY = -1; mpose.armRY = -1
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
                    let x = (cx + cos(a) * sp * age).rounded()
                    let y = (headY - 10 - abs(sin(a)) * sp * 1.1 * age + 150 * age * age).rounded()
                    c.fill(Path(CGRect(x: x, y: y, width: u, height: u)), with: .color(confetti[i % 6].opacity(max(0, 1 - age / 2))), style: FillStyle(antialiased: false))
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
            pen.px(8 + cellStep(t, 1.6) * 2, -1, .white.opacity(0.9))
        case "dream":
            pen.circleCells(6, -2, 1, .white.opacity(0.8))
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
