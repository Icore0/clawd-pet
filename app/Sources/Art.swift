import SwiftUI

// Wigglet's pixel art on a 24 x 16 grid: body 16 x 12, four 2-wide legs, 4 x 4 hands, 2 x 2 eyes.
// That's the official mascot's proportions at twice the resolution, so faces, hands and props can say more.
// Everything here draws through `Pen` in whole sprite pixels.

enum Pal {
    static let body = wiggletOrange
    static let bodyDark = wiggletDark
    static let mitt = Color(red: 0.94, green: 0.58, blue: 0.45)
    static let mini = Color(red: 0.95, green: 0.68, blue: 0.5)
    static let ink = Color(red: 0.07, green: 0.06, blue: 0.06)
    static let tongue = Color(red: 0.93, green: 0.42, blue: 0.48)
    static let blush = Color(red: 1, green: 0.55, blue: 0.62)
    static let white = Color(red: 0.97, green: 0.96, blue: 0.94)
    static let paper = Color(red: 0.96, green: 0.94, blue: 0.89)
    static let paperShade = Color(red: 0.82, green: 0.79, blue: 0.72)
    static let line = Color(red: 0.55, green: 0.53, blue: 0.5)
    static let wood = Color(red: 0.6, green: 0.4, blue: 0.24)
    static let woodDark = Color(red: 0.42, green: 0.27, blue: 0.16)
    static let tape = Color(red: 0.92, green: 0.82, blue: 0.56)
    static let steel = Color(red: 0.66, green: 0.68, blue: 0.72)
    static let steelDark = Color(red: 0.4, green: 0.42, blue: 0.46)
    static let screen = Color(red: 0.1, green: 0.11, blue: 0.14)
    static let laptop = Color(red: 0.55, green: 0.56, blue: 0.6)
    static let laptopDark = Color(red: 0.36, green: 0.37, blue: 0.41)
    static let glass = Color(red: 0.8, green: 0.9, blue: 0.96)
    static let glassRim = Color(red: 0.88, green: 0.9, blue: 0.93)
    static let ocean = Color(red: 0.24, green: 0.48, blue: 0.85)
    static let land = Color(red: 0.36, green: 0.75, blue: 0.42)
    static let green = Color(red: 0.36, green: 0.8, blue: 0.45)
    static let red = Color(red: 0.92, green: 0.3, blue: 0.3)
    static let yellow = Color(red: 1, green: 0.82, blue: 0.25)
    static let orange = Color(red: 0.96, green: 0.6, blue: 0.24)
    static let cyan = Color(red: 0.45, green: 0.8, blue: 0.95)
    static let pink = Color(red: 1, green: 0.48, blue: 0.66)
    static let purple = Color(red: 0.7, green: 0.5, blue: 0.95)
    static let navy = Color(red: 0.27, green: 0.33, blue: 0.7)
    static let smoke = Color(red: 0.72, green: 0.72, blue: 0.74)
    static let confetti: [Color] = [yellow, pink, cyan, green, orange, purple]
}

extension Pen {
    /// A two-pixel-thick line (arms, handles, strings).
    func thick(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ col: Color) {
        var x = x0, y = y0
        let dx = abs(x1 - x0), dy = abs(y1 - y0), sx = x0 < x1 ? 1 : -1, sy = y0 < y1 ? 1 : -1
        var err = dx - dy
        while true {
            rect(Double(x), Double(y), 2, 2, col)
            if x == x1 && y == y1 { break }
            let e2 = 2 * err
            if e2 > -dy { err -= dy; x += sx }
            if e2 < dx { err += dx; y += sy }
        }
    }
    /// Circle outline; `upper` keeps only the top half (signal arcs).
    func ring(_ cx: Int, _ cy: Int, _ r: Int, _ col: Color, upper: Bool = false) {
        var x = r, y = 0, err = 1 - r
        while x >= y {
            for (a, b) in [(x, y), (y, x), (-y, x), (-x, y), (-x, -y), (-y, -x), (y, -x), (x, -y)] where !upper || b < 0 { px(cx + a, cy + b, col) }
            y += 1
            if err < 0 { err += 2 * y + 1 } else { x -= 1; err += 2 * (y - x) + 1 }
        }
    }
    /// A small bitmap: `#` uses `col`, `o` uses `alt`.
    func bitmap(_ rows: [String], _ x: Int, _ y: Int, _ col: Color, alt: Color? = nil) {
        for (j, row) in rows.enumerated() {
            for (i, ch) in row.enumerated() {
                if ch == "#" { px(x + i, y + j, col) } else if ch == "o", let alt { px(x + i, y + j, alt) }
            }
        }
    }
}

/// Body geometry for a pose. Feet always end on the ground row (y 16).
struct Frame {
    let bx: Int, top: Int, bodyH: Int, legH: Int
    init(_ p: Pose) {
        bx = 4 + max(-2, min(2, p.lean))
        let drop = p.crouch ? 2 : 0
        top = p.squash + drop
        bodyH = 12 - p.squash
        legH = 4 - drop
    }
    var left: (x: Int, y: Int) { (bx, top) }
    func leftHand(_ p: Pose) -> (x: Int, y: Int) { (bx - 4 + p.armLX, top + 4 + p.armLY) }
    func rightHand(_ p: Pose) -> (x: Int, y: Int) { (bx + 16 - p.armRX, top + 4 + p.armRY) }
}

func drawWigglet(_ p: Pen, _ pose: Pose, color: Color = Pal.body, eyes: Bool = true, arms: Bool = true, accent: Color? = nil) {
    let f = Frame(pose)
    let bx = f.bx, top = f.top
    p.layer = .body
    p.rect(Double(bx), Double(top), 16, Double(f.bodyH), color)
    switch pose.profile {
    case .right: p.rect(Double(bx), Double(top), 2, Double(f.bodyH), Pal.bodyDark)
    case .left: p.rect(Double(bx + 14), Double(top), 2, Double(f.bodyH), Pal.bodyDark)
    case .back:
        p.rect(Double(bx), Double(top), 2, Double(f.bodyH), Pal.bodyDark)
        p.rect(Double(bx + 14), Double(top), 2, Double(f.bodyH), Pal.bodyDark)
    case .none: break
    }
    if let accent, f.bodyH > 9 { p.rect(Double(bx), Double(top + 8), 16, 2, accent) }
    p.layer = .leg
    for (i, col) in [0, 4, 10, 14].enumerated() {
        let x = bx + col + pose.legX[i]
        let h = max(1, f.legH - pose.leg[i])
        p.rect(Double(x), Double(top + f.bodyH), 2, Double(h), color)
        if pose.crouch { p.rect(Double(i < 2 ? x - 1 : x + 2), 15, 1, 1, color) }
    }
    if arms { drawArms(p, pose, color: color) }
    p.layer = .body
    if eyes { drawFace(p, pose, f) }
}

/// Hands are 4 x 4. A hand away from its shoulder gets an arm, so a raised hand never floats.
func drawArms(_ p: Pen, _ pose: Pose, color: Color = Pal.body) {
    let f = Frame(pose)
    let was = p.layer
    p.layer = .arm
    defer { p.layer = was }
    for side in 0..<2 {
        let h = side == 0 ? f.leftHand(pose) : f.rightHand(pose)
        let nubX = side == 0 ? f.bx - 4 : f.bx + 16
        _ = nubX
        let touching = h.x + 4 >= f.bx && h.x <= f.bx + 15 && h.y + 4 >= f.top && h.y <= f.top + f.bodyH
        let overBody = h.x + 4 >= f.bx + 2 && h.x <= f.bx + 14 && h.y + 4 > f.top && h.y < f.top + f.bodyH
        if !touching {
            let sx = side == 0 ? f.bx - 1 : f.bx + 15
            p.thick(sx, f.top + 5, h.x + 1, h.y + 1, color)
        }
        if overBody && color == Pal.body {
            // A hand in front of the body would vanish in the same color: lighter mitt, shaded edge.
            p.rect(Double(h.x), Double(h.y), 4, 4, Pal.mitt)
            p.rect(Double(h.x), Double(h.y + 3), 4, 1, Pal.bodyDark)
            p.rect(Double(side == 0 ? h.x + 3 : h.x), Double(h.y), 1, 3, Pal.bodyDark)
        } else {
            p.rect(Double(h.x), Double(h.y), 4, 4, color)
        }
    }
}

func drawFace(_ p: Pen, _ pose: Pose, _ f: Frame) {
    guard pose.profile != .back else { return }
    let bx = f.bx, top = f.top
    let xs: [Int]
    switch pose.profile {
    case .right: xs = [bx + 7, bx + 13]
    case .left: xs = [bx + 1, bx + 7]
    default: xs = [bx + 2, bx + 12]
    }
    p.layer = .eye
    defer { p.layer = .body }
    let ey = top + 2 + pose.lookY
    for (n, x0) in xs.enumerated() {
        let x = x0 + pose.lookX
        switch pose.eyes {
        case .open: p.rect(Double(x), Double(ey), 2, 2, Pal.ink)
        case .tall: p.rect(Double(x), Double(ey - 1), 2, 3, Pal.ink)
        case .closed: p.rect(Double(x), Double(ey + 1), 2, 1, Pal.ink)
        case .happy: p.bitmap([".##.", "#..#"], x - 1, ey, Pal.ink)
        case .cross: p.bitmap(n == 0 ? ["#.", ".#", ".#", "#."] : [".#", "#.", "#.", ".#"], x, ey - 1, Pal.ink)
        case .spiral: p.bitmap(["###", "#.#", "##."], x - (n == 0 ? 0 : 1), ey - 1, Pal.ink)
        }
    }
    if pose.blush {
        p.rect(Double(bx + 1), Double(top + 5), 2, 1, Pal.blush)
        p.rect(Double(bx + 13), Double(top + 5), 2, 1, Pal.blush)
    }
    let mx = (pose.profile == .right ? bx + 10 : pose.profile == .left ? bx + 4 : bx + 7) + pose.lookX
    let my = top + 6
    switch pose.mouth {
    case .none: break
    case .smile: p.bitmap(["#..#", ".##."], mx - 1, my, Pal.ink)
    case .open: p.rect(Double(mx - 1), Double(my), 4, 2, Pal.ink); p.rect(Double(mx), Double(my + 1), 2, 1, Pal.tongue)
    case .o: p.rect(Double(mx), Double(my), 2, 2, Pal.ink)
    case .yawn: p.rect(Double(mx - 1), Double(my - 1), 4, 4, Pal.ink); p.rect(Double(mx), Double(my + 1), 2, 2, Pal.tongue)
    case .wavy: p.bitmap([".#.#", "#.#."], mx - 1, my, Pal.ink)
    case .flat: p.rect(Double(mx - 1), Double(my), 4, 1, Pal.ink)
    }
}

/// A helper Wigglet at half size (the original 12 x 8 mascot), feet on row `g`.
func drawMini(_ p: Pen, x: Int, g: Int, hop: Int = 0, armsUp: Bool = false) {
    let y = g - 8 - hop, c = Pal.mini
    p.rect(Double(x + 2), Double(y), 8, 6, c)
    p.px(x + 3, y + 2, Pal.ink); p.px(x + 8, y + 2, Pal.ink)
    p.rect(Double(x), Double(armsUp ? y - 1 : y + 2), 2, 2, c); p.rect(Double(x + 10), Double(armsUp ? y - 1 : y + 2), 2, 2, c)
    for lx in [2, 4, 7, 9] { p.rect(Double(x + lx), Double(y + 6), 1, 2, c) }
}

extension Renderer {
    // MARK: geometry shared with the audits
    func leftHand(_ p: Pose) -> (x: Int, y: Int) { Frame(p).leftHand(p) }
    func rightHand(_ p: Pose) -> (x: Int, y: Int) { Frame(p).rightHand(p) }
    func bodyTop(_ p: Pose) -> Int { Frame(p).top }

    /// How far above the head a clip draws, in sprite pixels, so the speech bubble sits above it.
    static let overhead: [String: Int] = [
        "think": 13, "chatThink": 11, "git": 18, "deploy": 22, "done": 12, "testPass": 12, "testFail": 10, "dream": 15,
        "sleep": 11, "nap": 8, "nightcap": 13, "rateLimited": 14, "timeout": 13, "offline": 12, "outOfCredits": 11,
        "juggle": 12, "confetti": 14, "dizzy": 6, "conflict": 12, "web": 9, "flag": 16, "agent": 7, "stretch": 7,
        "ask": 8, "test": 9, "build": 10, "push": 12, "pull": 14, "install": 10, "hum": 10, "dance": 10, "pet": 10,
        "hop": 9, "wave": 7, "hello": 7, "bye": 7, "highFive": 7, "drag": 7, "grind": 6, "listen": 4, "chatTalk": 4,
    ]

    // MARK: sprite
    /// Body, carried prop, hands, hat, then anything worn on a hand.
    func paintSprite(_ pen: Pen, _ pose: Pose, _ name: String, _ t: Double, _ age: Double, accent: Color? = nil) {
        let frame = clipFrame(name, age: age)
        let wall = Int((snap12(t) * 12).rounded())
        pen.fade = pose.fade
        defer { pen.fade = 0 }
        drawWigglet(pen, pose, arms: false, accent: accent)
        let was = pen.layer
        pen.layer = .prop
        drawProp(pen, name, pose, frame, wall)
        pen.layer = was
        drawArms(pen, pose)
        pen.layer = .hat
        drawHat(pen, name, pose, frame)
        pen.layer = .prop
        drawWorn(pen, name, pose, wall)
        pen.layer = was
    }

    func drawProp(_ p: Pen, _ name: String, _ pose: Pose, _ frame: Int, _ wall: Int) {
        let f = Frame(pose), bx = f.bx, tp = f.top
        let l = f.leftHand(pose), r = f.rightHand(pose)
        func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) { p.rect(Double(x), Double(y), Double(w), Double(h), c) }
        func X(_ x: Int, _ y: Int, _ c: Color) { p.px(x, y, c) }
        switch name {
        case "read":
            // Open book below the eyes: cover, two pages, gutter, lines of text.
            R(bx + 1, tp + 5, 14, 8, Pal.woodDark)
            R(bx + 2, tp + 5, 12, 7, Pal.paper)
            R(bx + 7, tp + 5, 2, 7, Pal.paperShade)
            let turned = frame >= 46
            for (i, row) in [tp + 6, tp + 8, tp + 10].enumerated() {
                let a = turned ? [3, 4, 2][i] : [4, 3, 4][i], b = turned ? [4, 2, 3][i] : [3, 4, 2][i]
                R(bx + 3, row, a, 1, Pal.line); R(bx + 9, row, b, 1, Pal.line)
            }
            if frame >= 40 && frame < 46 {
                // The page lifts on the right, stands up, and lays down on the left.
                switch (frame - 40) / 2 {
                case 0: R(bx + 10, tp + 4, 4, 8, Pal.paper); R(bx + 10, tp + 4, 1, 8, Pal.paperShade)
                case 1: R(bx + 7, tp + 2, 2, 10, Pal.paper); R(bx + 8, tp + 2, 1, 10, Pal.paperShade)
                default: R(bx + 2, tp + 4, 4, 8, Pal.paper); R(bx + 5, tp + 4, 1, 8, Pal.paperShade)
                }
            }
        case "edit", "frantic":
            drawLaptop(p, frame: name == "frantic" ? wall * 3 : wall)
        case "search":
            drawLens(p, cx: r.x - 2, cy: r.y - 2, radius: 4, handle: r, eyes: eyeCenters(pose))
        case "webSearch":
            drawLens(p, cx: r.x - 2, cy: r.y - 2, radius: 4, handle: r, eyes: [])
            drawGlobe(p, cx: r.x - 2, cy: r.y - 2, radius: 3, phase: wall / 2)
            p.ring(r.x - 2, r.y - 2, 4, Pal.steelDark)
        case "web":
            drawGlobe(p, cx: bx + 8, cy: tp + 8, radius: 4, phase: wall / 2)
        case "plan":
            R(bx + 1, tp + 5, 11, 11, Pal.wood)
            R(bx + 2, tp + 7, 9, 8, Pal.paper)
            R(bx + 4, tp + 5, 5, 2, Pal.steel)
            for (i, row) in [tp + 7, tp + 10, tp + 13].enumerated() {
                R(bx + 3, row, 2, 2, Pal.paperShade)
                R(bx + 7, row + 1, 3, 1, Pal.line)
                if frame >= 6 * i + 4 { p.bitmap(["...#", "#.#.", ".#.."], bx + 3, row - 1, Pal.green) }
            }
            // Pencil held point down, tip just left of the hand.
            X(r.x + 1, r.y + 3, Pal.yellow); X(r.x, r.y + 4, Pal.yellow); X(r.x - 1, r.y + 5, Pal.ink); X(r.x + 2, r.y - 1, Pal.pink)
        case "test", "testPass", "testFail":
            let liquid: Color
            switch name {
            case "testPass": liquid = frame >= 6 ? Pal.green : Pal.purple
            case "testFail": liquid = frame >= 4 ? Pal.red : Pal.purple
            default: liquid = [Pal.purple, Pal.cyan, Pal.green][(wall / 24) % 3]
            }
            drawTube(p, x: r.x + 1, y: r.y - 7, liquid: liquid, bubble: wall)
        case "build":
            // A block beside Wigglet with a nail that sinks a little on each hit.
            let nail = frame >= 24 ? 0 : (frame >= 9 ? 2 : 4)
            R(20, 13, 8, 3, Pal.wood); R(20, 15, 8, 1, Pal.woodDark)
            if nail > 0 { R(23, 13 - nail, 2, nail, Pal.steel) }
            R(22, 12 - nail, 4, 1, Pal.steelDark)
            if pose.armRY <= -5 {
                R(r.x + 1, r.y - 5, 2, 6, Pal.wood)
                R(r.x - 2, r.y - 8, 8, 3, Pal.steel); R(r.x - 2, r.y - 6, 8, 1, Pal.steelDark)
            } else if pose.armRY >= 3 {
                p.thick(r.x + 2, r.y + 1, 23, 10 - nail, Pal.wood)
                R(21, 8 - nail, 6, 3, Pal.steel); R(21, 10 - nail, 6, 1, Pal.steelDark)
            } else {
                R(r.x + 3, r.y + 1, 5, 2, Pal.wood)
                R(r.x + 8, r.y - 2, 3, 7, Pal.steel); R(r.x + 10, r.y - 2, 1, 7, Pal.steelDark)
            }
        case "install":
            if frame < 34 {
                let y = frame < 8 ? tp + 4 - (8 - frame) * 4 : tp + 4
                drawBox(p, x: bx + 2, y: y, w: 12, h: 6)
                if frame >= 20 {
                    p.thick(bx + 2, y, bx - 1, y - 3, Pal.wood)
                    p.thick(bx + 12, y, bx + 15, y - 3, Pal.wood)
                }
            }
        case "deploy":
            if frame < 12 { drawRocket(p, cx: r.x + 2, y: r.y - 9, flame: false, wall: wall) }
            else if frame < 40 {
                let y = (tp - 14) - (frame - 12) * 3
                if y > -60 { drawRocket(p, cx: bx + 18, y: y, flame: true, wall: wall) }
            }
        case "push":
            if frame < 10 { p.bitmap(["....##.", "..####.", "#######", ".ooo..."], r.x - 2, r.y - 4, Pal.white, alt: Pal.paperShade) }
            else if frame < 28 {
                let k = frame - 10
                let x = bx + 16 + k * 2, y = tp - 8 - k * 2
                p.bitmap(["....##.", "..####.", "#######", ".ooo..."], x, y, Pal.white, alt: Pal.paperShade)
                for d in 1...3 where k - d * 2 >= 0 { X(x - d * 4, y + 3 + d * 4, d == 1 ? Pal.white : Pal.smoke) }
            }
        case "pull":
            let landed = frame >= 24
            let py = landed ? tp + 4 : tp + 4 - (24 - frame) * 2
            if !landed {
                p.bitmap(["..########..", ".##########.", "############", "#.#.#..#.#.#"], bx + 2, py - 10, Pal.white)
                for i in stride(from: 2, to: 12, by: 4) { R(bx + 2 + i, py - 9, 2, 2, Pal.orange) }
                p.lineCells(bx + 3, py - 6, bx + 5, py, Pal.line); p.lineCells(bx + 12, py - 6, bx + 10, py, Pal.line)
            } else if frame < 32 {
                let k = frame - 24
                R(bx + 12 + k / 2, tp + 2 + k, max(1, 8 - k), 2, Pal.white)
            }
            drawBox(p, x: bx + 4, y: py, w: 8, h: 6)
        case "tea":
            drawMug(p, x: r.x - 4, y: r.y - 1, color: Pal.white)
        case "nightcap":
            drawMug(p, x: bx + 5, y: tp + 6, color: Pal.navy)
        case "flag":
            R(r.x + 2, r.y - 11, 1, 15, Pal.white)
            for i in 0..<8 {
                let dy = ((i + wall / 3) / 2) % 2
                R(r.x + 3 + i, r.y - 11 + dy, 1, 5, i % 3 == 2 ? Pal.orange.opacity(0.85) : Pal.orange)
            }
        case "handoff", "parcel":
            if frame < 8 { drawBox(p, x: bx + 4, y: tp + 4, w: 8, h: 6) }
            else if frame < 14 { drawBox(p, x: r.x + 1, y: r.y - 4, w: 8, h: 6) }
        case "conflict":
            let shake = frame >= 10 && wall % 2 == 0 ? 1 : 0
            for h in [l, r] { R(h.x, h.y - 8 + shake, 5, 7, Pal.paper); R(h.x + 1, h.y - 6 + shake, 3, 1, Pal.line); R(h.x + 1, h.y - 4 + shake, 2, 1, Pal.line) }
        case "confetti":
            let h = frame < 6 ? r : f.rightHand(pose)
            p.bitmap(["...#", "..##", ".###", "####"], h.x, h.y - 4, Pal.orange, alt: Pal.purple)
            R(h.x + 1, h.y - 2, 1, 1, Pal.purple); R(h.x + 2, h.y - 3, 1, 1, Pal.purple)
        case "offline":
            R(r.x - 3, r.y, 4, 4, Pal.steelDark)
            R(r.x - 5, r.y, 2, 1, Pal.steel); R(r.x - 5, r.y + 3, 2, 1, Pal.steel)
            p.lineCells(r.x + 2, r.y + 4, r.x + 4, 15, Pal.steelDark); R(r.x + 4, 15, 6, 1, Pal.steelDark)
        case "outOfCredits":
            R(bx + 4, tp + 3, 8, 1, Pal.wood)
            R(bx + 4, tp + 4, 8, 7, Pal.glass)
            R(bx + 4, tp + 4, 1, 7, Pal.glassRim); R(bx + 11, tp + 4, 1, 7, Pal.glassRim); R(bx + 4, tp + 10, 8, 1, Pal.glassRim)
            if frame >= 6 && frame < 14 { X(bx + 7 + (wall % 2), tp + 9, Pal.paperShade) }
        default: break
        }
    }

    /// Things worn on a hand, drawn over it.
    func drawWorn(_ p: Pen, _ name: String, _ pose: Pose, _ wall: Int) {
        guard name == "watch" else { return }
        let l = Frame(pose).leftHand(pose)
        if pose.armLX >= 4 {
            // A watch on the raised wrist: dark band, white face, a ticking red hand.
            p.rect(Double(l.x), Double(l.y + 1), 4, 2, Pal.screen)
            p.rect(Double(l.x + 1), Double(l.y), 3, 3, Pal.screen)
            p.rect(Double(l.x + 1), Double(l.y), 2, 2, Pal.white)
            p.px(l.x + [1, 2, 2, 1][(wall / 3) % 4], l.y + [0, 0, 1, 1][(wall / 3) % 4], Pal.red)
        }
    }

    func drawHat(_ p: Pen, _ name: String, _ pose: Pose, _ frame: Int) {
        let f = Frame(pose), bx = f.bx, tp = f.top
        func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) { p.rect(Double(x), Double(y), Double(w), Double(h), c) }
        switch name {
        case "build":
            R(bx + 3, tp - 4, 10, 1, Pal.yellow); R(bx + 2, tp - 3, 12, 2, Pal.yellow)
            R(bx, tp - 1, 16, 1, Pal.orange); R(bx + 7, tp - 4, 2, 3, Pal.orange)
        case "test", "testPass", "testFail":
            R(bx, tp + 3, 16, 1, Pal.screen)
            for x in [bx + 1, bx + 11] {
                R(x, tp + 1, 4, 1, Pal.steel); R(x, tp + 4, 4, 1, Pal.steel)
                R(x, tp + 1, 1, 4, Pal.steel); R(x + 3, tp + 1, 1, 4, Pal.steel)
            }
        case "sleep", "nap", "nightcap":
            R(bx + 2, tp - 1, 12, 1, Pal.white)
            R(bx + 3, tp - 3, 10, 2, Pal.navy); R(bx + 6, tp - 5, 8, 2, Pal.navy); R(bx + 11, tp - 6, 4, 1, Pal.navy)
            R(bx + 15, tp - 7, 2, 2, Pal.white)
        default: break
        }
    }

    // MARK: props
    func eyeCenters(_ pose: Pose) -> [(Int, Int)] {
        let f = Frame(pose)
        return [(f.bx + 3 + pose.lookX, f.top + 3), (f.bx + 13 + pose.lookX, f.top + 3)]
    }

    func drawLaptop(_ p: Pen, frame: Int) {
        p.rect(3, 13, 18, 3, Pal.laptop); p.rect(3, 15, 18, 1, Pal.laptopDark)
        for x in stride(from: 5, to: 19, by: 2) { p.px(x, 14, Pal.laptopDark) }
        p.rect(6, 7, 12, 6, Pal.laptopDark)
        p.rect(7, 8, 10, 4, Pal.screen)
        // Code scrolls a line every half second; the bottom line types out with a blinking cursor.
        let rows: [(Int, Int, Color)] = [(0, 5, Pal.orange), (1, 6, Pal.white), (1, 4, Pal.cyan), (0, 3, Pal.orange), (2, 5, Pal.white), (1, 7, Pal.green)]
        let shift = frame / 6
        for i in 0..<4 {
            let row = rows[(shift + i) % rows.count]
            let len = i == 3 ? min(row.1, (frame % 6) + 1) : row.1
            p.rect(Double(8 + row.0), Double(8 + i), Double(len), 1, row.2)
            if i == 3 && frame % 4 < 2 { p.px(8 + row.0 + len, 11, Pal.white) }
        }
    }

    func drawLens(_ p: Pen, cx: Int, cy: Int, radius: Int, handle: (x: Int, y: Int), eyes: [(Int, Int)]) {
        p.thick(handle.x + 1, handle.y + 1, cx + radius / 2 + 1, cy + radius / 2 + 1, Pal.woodDark)
        p.circleCells(cx, cy, radius, Pal.glass)
        if let eye = eyes.first(where: { abs($0.0 - cx) <= 2 && abs($0.1 - cy) <= 3 }) {
            _ = eye
            p.rect(Double(cx - 1), Double(cy - 2), 3, 4, Pal.ink)
            p.px(cx, cy - 1, Pal.white)
        }
        p.ring(cx, cy, radius, Pal.steelDark)
        p.px(cx - radius + 2, cy - radius + 2, Pal.white)
    }

    func drawGlobe(_ p: Pen, cx: Int, cy: Int, radius: Int, phase: Int) {
        p.circleCells(cx, cy, radius, Pal.ocean)
        let map = ["..##.....#..", ".###....###.", "..#....####.", "......##.#..", "..##.....#..", ".####.......", "..##....##..", "........#..."]
        for dy in -radius...radius {
            for dx in -radius...radius where dx * dx + dy * dy <= radius * radius {
                let row = map[(dy + radius) % map.count]
                let col = Array(row)[((dx + phase) % 12 + 12) % 12]
                if col == "#" { p.px(cx + dx, cy + dy, Pal.land) }
            }
        }
        p.px(cx - radius / 2, cy - radius / 2, Pal.white)
    }

    func drawTube(_ p: Pen, x: Int, y: Int, liquid: Color, bubble: Int) {
        p.rect(Double(x - 1), Double(y), 5, 1, Pal.glassRim)
        p.rect(Double(x), Double(y + 1), 3, 9, Pal.glass)
        p.rect(Double(x), Double(y + 4), 3, 6, liquid)
        p.px(x + 1, y + 9 - (bubble / 2) % 5, Pal.white)
    }

    func drawBox(_ p: Pen, x: Int, y: Int, w: Int, h: Int) {
        p.rect(Double(x), Double(y), Double(w), Double(h), Pal.wood)
        p.rect(Double(x), Double(y + h - 1), Double(w), 1, Pal.woodDark)
        p.rect(Double(x + w / 2 - 1), Double(y), 2, Double(h), Pal.tape)
    }

    func drawRocket(_ p: Pen, cx: Int, y: Int, flame: Bool, wall: Int) {
        p.px(cx, y, Pal.red); p.rect(Double(cx - 1), Double(y + 1), 3, 1, Pal.red)
        p.rect(Double(cx - 1), Double(y + 2), 3, 7, Pal.white)
        p.px(cx, y + 4, Pal.cyan)
        p.rect(Double(cx - 2), Double(y + 6), 1, 3, Pal.red); p.rect(Double(cx + 2), Double(y + 6), 1, 3, Pal.red)
        p.rect(Double(cx - 1), Double(y + 9), 3, 1, Pal.steelDark)
        if flame {
            p.rect(Double(cx - 1), Double(y + 10), 3, 2, Pal.yellow)
            p.px(cx, y + 12 + wall % 2, Pal.orange)
        }
    }

    func drawMug(_ p: Pen, x: Int, y: Int, color: Color) {
        p.rect(Double(x), Double(y), 5, 5, color)
        p.rect(Double(x + 1), Double(y), 3, 1, Pal.woodDark)
        p.rect(Double(x + 5), Double(y + 1), 1, 3, color)
    }

    // MARK: effects
    static let glyphs: [String: [String]] = [
        "?": [".###.", "#...#", "....#", "..##.", "..#..", ".....", "..#.."],
        "!": ["##", "##", "##", "##", "..", "##"],
        "check": ["......#", ".....##", "#...##.", "##.##..", ".###...", "..#...."],
        "x": ["#...#", ".#.#.", "..#..", ".#.#.", "#...#"],
        "heart": [".##.##.", "#######", "#######", ".#####.", "..###..", "...#..."],
        "note": ["..###", "..#.#", "..#..", "###..", "###.."],
        "spark": ["..#..", "..#..", "##.##", "..#..", "..#.."],
        "star": [".#.", "###", ".#."],
        "Z": ["#####", "...#.", "..#..", ".#...", "#####"],
        "z": ["###", ".#.", "###"],
        "down": ["..#..", "..#..", "..#..", "#####", ".###.", "..#.."],
        "1": [".#.", "##.", ".#.", ".#.", "###"],
        "2": ["###", "..#", "###", "#..", "###"],
        "3": ["###", "..#", ".##", "..#", "###"],
        "0": ["###", "#.#", "#.#", "#.#", "###"],
        "moon": [".##", "##.", "#..", "##.", ".##"],
    ]
    func glyph(_ p: Pen, _ name: String, _ x: Int, _ y: Int, _ c: Color) { p.bitmap(Renderer.glyphs[name] ?? [], x, y, c) }

    /// Effects for clip `b`. `frame` counts from the clip start, `wall` is the free-running 12 fps clock.
    func paintEffects(_ p: Pen, _ b: String, _ pose: Pose, frame: Int, t: Double, session: SessionPet?, now: Date) {
        let was = p.layer
        p.layer = .fx
        defer { p.layer = was }
        let wall = Int((snap12(t) * 12).rounded())
        let f = Frame(pose), bx = f.bx, tp = f.top
        let r = f.rightHand(pose)
        func R(_ x: Int, _ y: Int, _ w: Int, _ h: Int, _ c: Color) { p.rect(Double(x), Double(y), Double(w), Double(h), c) }
        func burst(_ n: Int, from k: Int) {
            for i in 0..<n {
                let a = Double(i) / Double(n) * 2 * .pi, d = Double(k) * 1.6
                p.rect(Double(12 + Int(cos(a) * d)), Double(-2 + Int(sin(a) * d * 0.7) + k / 2), 2, 1, Pal.confetti[i % 6])
            }
        }
        func rain(_ n: Int, _ k: Int) {
            for i in 0..<n {
                let x = (i * 7 + 1) % 26 - 1, y = -14 + ((k / 2 + i * 5) % 26)
                R(x, y, 2, 1, Pal.confetti[i % 6])
            }
        }
        switch b {
        case "think", "chatThink":
            let lit = (wall / 4) % 4
            for (i, s) in [(18, -1, 1), (20, -4, 2), (22, -8, 3)].enumerated() where i < lit { R(s.0, s.1, s.2, s.2, Pal.white) }
            if b == "think" && frame >= 28 {
                p.bitmap([".###.", "#####", "#####", ".###.", ".ooo.", "..o.."], 9, -12, Pal.yellow, alt: Pal.steel)
                if wall % 4 < 2 { p.px(7, -12, Pal.yellow); p.px(15, -12, Pal.yellow); p.px(11, -14, Pal.yellow) }
            }
            if b == "chatThink" {
                R(4, -10, 16, 6, Pal.white); R(6, -4, 2, 2, Pal.white)
                for i in 0..<3 { R(7 + i * 4, -8, 2, 2, (wall / 3) % 3 == i ? Pal.ink : Pal.paperShade) }
            }
        case "web":
            let level = (wall / 3) % 4
            for i in 0..<3 where i < level { p.ring(12, -1, 2 + i * 3, Pal.cyan, upper: true) }
        case "agent":
            drawMini(p, x: -13, g: 16, hop: (wall / 3) % 2 == 0 ? 2 : 0, armsUp: (wall / 6) % 2 == 0)
            drawMini(p, x: 25, g: 16, hop: (wall / 3) % 2 == 1 ? 2 : 0, armsUp: (wall / 6) % 2 == 1)
        case "git":
            let white = Pal.white, lit = Pal.orange
            p.rect(16, -15, 1, 11, white)
            if frame >= 6 { p.lineCells(16, -6, 21, -10, white) }
            if frame >= 22 { p.lineCells(21, -11, 17, -15, white) }
            for (i, n) in [(16, -5), (16, -10)].enumerated() { R(n.0 - 1, n.1 - 1, 3, 3, frame >= 16 && i == 1 ? lit : white) }
            if frame >= 10 { R(20, -12, 3, 3, lit) }
            if frame >= 22 { R(15, -16, 3, 3, Pal.green) }
        case "deploy":
            if frame < 12 { glyph(p, ["3", "2", "1"][min(2, frame / 4)], 5, -9, Pal.white) }
            else if frame < 22 {
                let k = frame - 12
                for i in 0..<3 where k > i { p.circleCells(bx + 15 + i * 4 - 4, tp - 4 + k / 4, min(2, (k - i) / 3), Pal.smoke) }
            }
        case "install":
            if frame >= 24 && frame < 34 {
                let k = frame - 24
                glyph(p, "spark", bx + 6, tp - 2 - k, Pal.yellow)
                p.px(bx + 3, tp - k, Pal.cyan); p.px(bx + 13, tp - 1 - k, Pal.pink)
            }
        case "pull":
            if frame < 24 && wall % 6 < 4 { glyph(p, "down", -1, -6, Pal.cyan) }
        case "done":
            if frame >= 4 { glyph(p, "check", 9, -12, Pal.green) }
            if frame >= 4 && frame < 22 { burst(10, from: frame - 3) }
        case "testPass":
            if frame >= 8 { glyph(p, "check", 9, -12, Pal.green); if frame < 24 { burst(8, from: frame - 7) } }
        case "testFail":
            if frame >= 4 && wall % 6 < 4 { glyph(p, "x", 10, -10, Pal.red) }
            if frame >= 4 && frame < 18 {
                let k = frame - 4
                p.circleCells(r.x + 2, r.y - 9 - k / 2, 1 + k / 5, Pal.smoke)
            }
        case "ask":
            glyph(p, "?", r.x + 5, r.y - 1 + ((wall / 6) % 2), Pal.yellow)
        case "oops":
            glyph(p, "!", 22, -3 + ((wall / 4) % 2), Pal.red)
            if frame >= 8 { R(bx - 1, tp + 2 + (wall / 3) % 4, 2, 3, Pal.cyan) }
        case "hello":
            if frame < 12 && wall % 4 < 2 { glyph(p, "spark", -2, 0, Pal.yellow); glyph(p, "spark", 20, -4, Pal.yellow) }
        case "sleep", "nap", "nightcap":
            let k = (wall / 4) % 10
            glyph(p, "Z", 17 + k / 3, -3 - k, Pal.white)
            let k2 = (wall / 4 + 5) % 10
            if k2 < 7 { glyph(p, "z", 19 + k2 / 3, -2 - k2, Pal.smoke) }
            if b == "nightcap" { glyph(p, "moon", 2, -11, Pal.yellow); p.px(7, -13, Pal.white); p.px(0, -7, Pal.white) }
        case "dream":
            for (i, c) in [(15, -1, 1), (17, -4, 1)].enumerated() where (wall / 6 + i) % 3 != 0 { p.circleCells(c.0, c.1, c.2, Pal.white) }
            for c in [(8, -10, 4), (13, -12, 4), (18, -10, 4), (13, -8, 4)] { p.circleCells(c.0, c.1, c.2, Pal.white) }
            glyph(p, wall % 12 < 6 ? "star" : "heart", wall % 12 < 6 ? 12 : 10, wall % 12 < 6 ? -12 : -13, wall % 12 < 6 ? Pal.yellow : Pal.pink)
        case "listen":
            let k = (wall / 3) % 3
            for i in 0..<2 { let x = 30 - k - i * 3; R(x, -1 + i, 1, 6 - 2 * i, Pal.red.opacity(i == 0 ? 1 : 0.7)) }
        case "chatTalk":
            if wall % 4 < 2 { R(bx + 17, tp + 5, 3, 1, Pal.white); R(bx + 17, tp + 8, 2, 1, Pal.white); p.px(bx + 18, tp + 3, Pal.white) }
        case "hum", "dance":
            let k = (wall / 3) % 12
            glyph(p, "note", 16 + k / 3, 2 - k, b == "hum" ? Pal.pink : Pal.yellow)
            if b == "dance" { let k2 = (wall / 3 + 6) % 12; glyph(p, "note", 2 - k2 / 4, 3 - k2, Pal.pink) }
        case "pet":
            for i in 0..<2 { glyph(p, "heart", 2 + i * 12, -4 - ((wall / 3 + i * 4) % 8), Pal.pink) }
        case "build":
            if (frame >= 9 && frame < 12) || (frame >= 24 && frame < 27) {
                glyph(p, "spark", 22, 2, Pal.yellow)
                p.px(19, 5, Pal.orange); p.px(29, 4, Pal.orange); p.px(27, 1, Pal.yellow)
            }
        case "juggle":
            for k in 0..<3 {
                let u = Double((wall + k * 8) % 24) / 24
                let x = 2 + Int(u * 18), y = tp + 1 - Int(13 * sin(.pi * u))
                R(x, y, 2, 2, [Pal.red, Pal.yellow, Pal.cyan][k])
            }
        case "tea":
            let k = (wall / 3) % 6
            p.px(r.x - 2 + (k % 2), r.y - 3 - k, Pal.smoke); p.px(r.x - 3 + ((k + 1) % 2), r.y - 6 - k / 2, Pal.smoke)
        case "sweat", "grind":
            let k = (wall / 2) % 8
            R(bx - 1, tp + 1 + k, 2, 3, Pal.cyan)
            if b == "sweat" { R(bx + 16, tp + 3 + (k + 4) % 8, 2, 3, Pal.cyan) }
        case "frantic":
            for (i, y) in [4, 8, 12].enumerated() where (wall + i) % 2 == 0 { R(21, y, 3, 1, Pal.white); R(-1, y + 1, 2, 1, Pal.white) }
            let k = wall % 12
            R(18 + k / 2, 2 - k, 3, 4, Pal.paper)
        case "watch":
            break
        case "flag":
            break
        case "confetti":
            if frame >= 6 { if frame < 12 { burst(12, from: frame - 5) } else { rain(14, wall) } }
        case "conflict":
            if frame >= 10 {
                if wall % 4 < 2 { p.bitmap([".#", "#.", ".#", "#."], 11, tp - 9, Pal.yellow) }
                glyph(p, "x", 10, -12, Pal.red)
            }
        case "dizzy":
            for k in 0..<3 {
                let a = Double(wall) * 0.5 + Double(k) * 2.09
                glyph(p, "star", 11 + Int(cos(a) * 9), -4 + Int(sin(a) * 2), Pal.yellow)
            }
        case "highFive":
            if frame >= 4 && frame < 10 { glyph(p, "spark", r.x + 3, r.y - 4, Pal.yellow) }
        case "hop":
            if frame < 2 { R(2, 15, 2, 1, Pal.smoke); R(20, 15, 2, 1, Pal.smoke) }
        case "handoff":
            let walk = max(0, frame - 18)
            let mx = 25 + walk
            if frame < 30 { drawMini(p, x: mx, g: 16, hop: walk % 4 < 2 && walk > 0 ? 1 : 0, armsUp: frame >= 14) }
            if frame >= 14 && frame < 30 { drawBox(p, x: mx + 2, y: 3 - (walk % 4 < 2 && walk > 0 ? 1 : 0), w: 8, h: 5) }
        case "parcel":
            if frame >= 14 && frame < 24 { drawBox(p, x: 26 + (frame - 14) * 2, y: 10, w: 8, h: 6) }
        case "offline":
            for rad in [2, 5, 8] { p.ring(19, -2, rad, Pal.white, upper: true) }
            p.rect(18, -3, 2, 2, Pal.white)
            if wall % 8 < 6 { p.thick(12, -11, 25, -1, Pal.red) }
        case "rateLimited":
            let k = min(4, (wall / 6) % 6)
            R(8, -14, 8, 1, Pal.wood); R(8, -3, 8, 1, Pal.wood)
            p.bitmap(["######", ".####.", "..##..", "..##..", ".####.", "######"], 9, -12, Pal.glass)
            R(10, -12 + k / 2, 4 - k / 2, max(0, 2 - k / 2), Pal.yellow)
            R(10, -6 + (4 - k) / 2, 4, max(1, k / 2 + 1), Pal.yellow)
            if (wall / 2) % 2 == 0 { p.px(11, -8, Pal.yellow) }
        case "timeout":
            p.circleCells(12, -8, 5, Pal.white); p.ring(12, -8, 5, Pal.red)
            R(8, -14, 2, 2, Pal.red); R(15, -14, 2, 2, Pal.red)
            let hand = frame < 24 ? [(0, -3), (2, -2), (3, 0), (2, 2), (0, 3), (-2, 2), (-3, 0), (-2, -2)][(wall) % 8] : (0, -3)
            p.lineCells(12, -8, 12 + hand.0, -8 + hand.1, Pal.ink)
        case "outOfCredits":
            p.circleCells(19, -6, 3, Pal.yellow); p.ring(19, -6, 3, Pal.orange)
            if wall % 8 < 6 { p.lineCells(15, -10, 23, -2, Pal.red) }
        default: break
        }
        // Hearts after a click.
        let ca = now.timeIntervalSince(m.clickAt)
        if let session, ca >= 0, ca < 1.6, session.sid == m.clickSid { glyph(p, "heart", 8, -4 - Int(ca * 8), Pal.pink) }
        // A helper per running sub-agent (the label shows the rest).
        if let n = session?.subagentCount, n > 0, b != "agent", b != "handoff" { drawMini(p, x: 25, g: 16) }
    }

    /// One glyph from a list of choices (used for countdown digits).
    func glyph(_ p: Pen, _ name: [String], _ x: Int, _ y: Int, _ c: Color) { p.bitmap(name, x, y, c) }
    func glyph(_ p: Pen, _ digit: String, _ x: Int, _ y: Int, _ c: Color, scale: Int) {
        for (j, row) in (Renderer.glyphs[digit] ?? []).enumerated() {
            for (i, ch) in row.enumerated() where ch == "#" { p.rect(Double(x + i * scale), Double(y + j * scale), Double(scale), Double(scale), c) }
        }
    }
}

/// Dev tool: `--sheet <dir>` writes one PNG per clip (12 frames across) plus `all.png`, for checking the art by eye.
func runAscii(_ id: String, _ f: Int) -> Int32 {
    let r = Renderer(m: PetModel())
    let t = Double(f) / 12
    let pose = r.pose(id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
    let pen = Pen(recordingU: 1)
    r.paintSprite(pen, pose, id, t, t)
    print(pose)
    for y in -4..<17 {
        var line = ""
        for x in -2..<26 {
            var ch = "."
            if let c = pen.cells[y]?[x] {
                let r = (c >> 24) & 255, g = (c >> 16) & 255, b = (c >> 8) & 255
                ch = r < 40 && g < 40 ? "#" : (r > 200 && g < 140 && b < 110 ? "o" : "+")
            }
            line += ch
        }
        print(line)
    }
    return 0
}

func runSheet(_ dir: String) -> Int32 {
    let r = Renderer(m: PetModel())
    let cell = 7, fx0 = -10, fy0 = -23, fw = 44, fh = 40, cols = 6
    try? FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
    var rows: [(String, CGImage)] = []
    for anim in AnimationCatalog.all {
        let n = AnimationData.frames[anim.id]?.count ?? 12
        let w = fw * cols * cell, h = fh * cell
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { continue }
        ctx.setFillColor(red: 0.08, green: 0.08, blue: 0.075, alpha: 1); ctx.fill(CGRect(x: 0, y: 0, width: w, height: h))
        for i in 0..<cols {
            let f = Int(Double(i) * Double(n) / Double(cols))
            let t = Double(f) / 12
            let pose = r.pose(anim.id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
            let pen = Pen(recordingU: 1)
            r.paintSprite(pen, pose, anim.id, t, t)
            r.paintEffects(pen, anim.id, pose, frame: r.clipFrame(anim.id, age: t), t: t, session: nil, now: Date.distantPast)
            ctx.setFillColor(red: 0.2, green: 0.2, blue: 0.19, alpha: 1)
            ctx.fill(CGRect(x: i * fw * cell, y: 0, width: 1, height: h))
            ctx.fill(CGRect(x: i * fw * cell, y: (fh - (16 - fy0) - pose.lift + 16 - 16) * cell - 1 + 0, width: fw * cell, height: 1))
            for (y, row) in pen.cells {
                for (x, c) in row {
                    let yy = y - pose.lift
                    let px = (x - fx0), py = (yy - fy0)
                    guard px >= 0, px < fw, py >= 0, py < fh else { continue }
                    ctx.setFillColor(red: CGFloat((c >> 24) & 255) / 255, green: CGFloat((c >> 16) & 255) / 255,
                                     blue: CGFloat((c >> 8) & 255) / 255, alpha: CGFloat(c & 255) / 255)
                    ctx.fill(CGRect(x: (i * fw + px) * cell, y: (fh - 1 - py) * cell, width: cell, height: cell))
                }
            }
        }
        if let img = ctx.makeImage() {
            rows.append((anim.id, img))
            let rep = NSBitmapImageRep(cgImage: img)
            try? rep.representation(using: .png, properties: [:])?.write(to: URL(fileURLWithPath: dir + "/" + anim.id + ".png"))
        }
    }
    print("wrote \(rows.count) sheets to \(dir)")
    return 0
}
