import Foundation

// Hand-authored frame data at 12 fps, in sprite pixels on a 24 x 16 grid (body 16 x 12, legs 4 tall, arms 4 x 4).
//
// Conventions (y grows down):
//  armLY/armRY move a hand up (-) or down (+); armLX/armRX > 0 bring a hand in front of the body, < 0 out to the side.
//  A hand far from its shoulder is drawn with an arm, so raised hands read as arms, not floating squares.
//  `hold` is how many frames a key stays on screen. Between keys the pose is tweened two pixels per frame,
//  taken from the end of the earlier key, so frame counts (and the props timed to them) never change.
//  `cut` marks an intended jump: no tween into that key.

struct Key {
    var pose: Pose
    var hold: Int
    var cut = false
}

struct ClipData {
    var keys: [Key]
    /// A prop in this clip is carried: it must touch a hand in every frame.
    var held = false
    /// Frames may leave the ground (jumps, dangling).
    var airborne = false
    /// Max changed pixels between two adjacent frames (shape only; translation is checked separately).
    var maxDelta = 90
    /// Tween the last key into the first (looping clips).
    var loops = true
    /// After the first pass a looping clip repeats from this frame (an intro such as a countdown plays once).
    var loopFrom = 0

    var frameCount: Int { keys.reduce(0) { $0 + $1.hold } }

    func index(_ frame: Int, loop: Bool) -> Int {
        let n = max(1, frameCount)
        if !loop { return min(max(0, frame), n - 1) }
        if frame < n || loopFrom <= 0 || loopFrom >= n { return ((frame % n) + n) % n }
        return loopFrom + (frame - loopFrom) % (n - loopFrom)
    }

    /// Every frame, with in-betweens.
    var frames: [Pose] { ClipData.expand(keys, loops: loops) }
    /// Frames that start a `cut` key: the audit allows a jump there.
    var cutFrames: Set<Int> {
        var out = Set<Int>(), acc = 0
        for k in keys { if k.cut { out.insert(acc) }; acc += k.hold }
        return out
    }

    static func expand(_ keys: [Key], loops: Bool) -> [Pose] {
        var out: [Pose] = []
        for k in keys { out += Array(repeating: k.pose, count: max(1, k.hold)) }
        var start = 0
        for (i, k) in keys.enumerated() {
            let h = max(1, k.hold)
            let nextIndex = i + 1 < keys.count ? i + 1 : (loops ? 0 : -1)
            if nextIndex >= 0, nextIndex != i, !keys[nextIndex].cut {
                let a = k.pose, b = keys[nextIndex].pose
                let steps = min(h - 1, max(0, Int((Double(a.distance(to: b)) / 2).rounded(.up)) - 1))
                if steps > 0 {
                    for j in 1...steps {
                        out[start + h - 1 - steps + j] = a.toward(b, Double(j) / Double(steps + 1))
                    }
                }
            }
            start += h
        }
        return out
    }
}

extension Pose {
    /// Largest change of any positional field, in pixels.
    func distance(to b: Pose) -> Int {
        var d = [abs(lean - b.lean), abs(squash - b.squash), abs(lift - b.lift), abs(dx - b.dx),
                 abs(armLX - b.armLX), abs(armLY - b.armLY), abs(armRX - b.armRX), abs(armRY - b.armRY)].max() ?? 0
        for i in 0..<4 { d = max(d, abs(leg[i] - b.leg[i]), abs(legX[i] - b.legX[i])) }
        return d
    }
    /// Positional fields moved a fraction of the way to `b`. Faces, profile and fades switch with the next key.
    func toward(_ b: Pose, _ f: Double) -> Pose {
        func m(_ x: Int, _ y: Int) -> Int { x + Int((Double(y - x) * f).rounded()) }
        var p = self
        p.lean = m(lean, b.lean); p.squash = m(squash, b.squash); p.lift = m(lift, b.lift); p.dx = m(dx, b.dx)
        p.armLX = m(armLX, b.armLX); p.armLY = m(armLY, b.armLY); p.armRX = m(armRX, b.armRX); p.armRY = m(armRY, b.armRY)
        for i in 0..<4 { p.leg[i] = m(leg[i], b.leg[i]); p.legX[i] = m(legX[i], b.legX[i]) }
        return p
    }
}

private func K(_ hold: Int, _ p: Pose = Pose(), cut: Bool = false) -> Key { Key(pose: p, hold: hold, cut: cut) }
private func P(_ f: (inout Pose) -> Void) -> Pose { Pose().with(f) }

enum AnimationData {
    // MARK: building blocks
    /// Both hands in front of the belly, carrying something between them.
    static let holdFront = P { $0.armLX = 4; $0.armLY = 3; $0.armRX = 4; $0.armRY = 3 }
    static let blink = P { $0.eyes = .closed }
    static let happy = P { $0.eyes = .happy; $0.mouth = .smile }
    static let armsUp = P { $0.armLY = -9; $0.armRY = -9; $0.armLX = 1; $0.armRX = 1 }
    /// Right hand on the chin, eyes up: thinking.
    static let chin = P { $0.armRX = 5; $0.armRY = 4; $0.lookY = -1 }
    /// Sitting at the laptop: body lowered, hands on the keys.
    static let desk = P { $0.crouch = true; $0.armLX = 3; $0.armLY = 6; $0.armRX = 3; $0.armRY = 6; $0.lookY = 1 }

    static func wave(_ base: Pose, cycles: Int, hold: Int = 3) -> [Key] {
        var keys: [Key] = []
        for _ in 0..<cycles {
            keys += [K(hold, base.with { $0.armRY = -9; $0.armRX = -1 }), K(hold, base.with { $0.armRY = -8; $0.armRX = 2 })]
        }
        return keys
    }

    // MARK: clips
    static let clips: [String: ClipData] = {
        var c: [String: ClipData] = [:]

        // ---------- work ----------
        // Eyes run along a line left to right, jump back, twice; then a page turns (frames 40...47).
        let book = holdFront.with { $0.lookY = 1; $0.armLY = 5; $0.armRY = 5 }
        c["read"] = ClipData(keys: [
            K(6, book.with { $0.lookX = -1 }), K(6, book), K(6, book.with { $0.lookX = 1 }),
            K(6, book.with { $0.lookX = -1 }, cut: true), K(6, book), K(5, book.with { $0.lookX = 1 }),
            K(1, book.with { $0.eyes = .closed }), K(4, book),
            K(8, book.with { $0.lookX = 1; $0.lookY = 0 })], held: true)

        // Typing on a laptop; a glance up over the screen.
        var edit: [Key] = []
        for i in 0..<8 { edit.append(K(2, desk.with { $0.armLY = i % 2 == 0 ? 5 : 6; $0.armRY = i % 2 == 0 ? 6 : 5 }, cut: i > 0)) }
        edit += [K(4, desk.with { $0.lookY = -1; $0.lookX = 1 }), K(1, desk.with { $0.eyes = .closed; $0.lookY = 0 }), K(3, desk.with { $0.lookY = 0 })]
        c["edit"] = ClipData(keys: edit)

        // A magnifier sweeps across the face; the eye under the lens shows big.
        let lens = P { $0.armRY = -1; $0.armRX = 2; $0.lookX = 1 }
        c["search"] = ClipData(keys: [
            K(8, lens), K(2, lens.with { $0.armRX = 6; $0.lean = -1 }), K(8, lens.with { $0.armRX = 10; $0.lookX = -1; $0.lean = -1 }),
            K(2, lens.with { $0.armRX = 6 }), K(6, lens), K(1, lens.with { $0.eyes = .closed }), K(9, lens)], held: true)

        // A spinning globe held at the belly.
        let globe = P { $0.armLX = 4; $0.armLY = 4; $0.armRX = 4; $0.armRY = 4 }
        c["web"] = ClipData(keys: [K(17, globe), K(1, globe.with { $0.eyes = .closed }), K(6, globe)], held: true)

        // Directs two helper Wigglets, one hand then the other.
        c["agent"] = ClipData(keys: [
            K(6, P { $0.armLY = -7; $0.armLX = -1; $0.lookX = -1; $0.mouth = .smile }),
            K(6, P { $0.armRY = -7; $0.armRX = -1; $0.lookX = 1; $0.mouth = .smile }),
            K(6, P { $0.armLY = -7; $0.armLX = -1; $0.lookX = -1 }),
            K(6, P { $0.armRY = -7; $0.armRX = -1; $0.lookX = 1 })])

        // Clipboard in the left hand; the pencil ticks three boxes.
        let board = P { $0.armLX = 5; $0.armLY = 5; $0.armRX = 2; $0.armRY = 2; $0.lookY = 1; $0.lookX = -1 }
        c["plan"] = ClipData(keys: [
            K(6, board.with { $0.armRX = 11; $0.armRY = -1 }), K(6, board.with { $0.armRX = 11; $0.armRY = 2 }),
            K(6, board.with { $0.armRX = 11; $0.armRY = 5 }), K(12, board.with { $0.mouth = .smile }), K(6, board)], held: true)

        // Shakes a test tube, then holds it up to the light.
        let tube = P { $0.armRY = -3; $0.armRX = 2; $0.lookX = 1; $0.lookY = -1 }
        var test: [Key] = []
        for i in 0..<4 { test.append(K(2, tube.with { $0.armRX = i % 2 == 0 ? 1 : 3 })) }
        test += [K(8, tube), K(8, tube.with { $0.armRY = -5; $0.eyes = .tall })]
        c["test"] = ClipData(keys: test, held: true)

        // Hammer up, swing, hit the nail (sparks), twice.
        let up = P { $0.armRY = -8; $0.armRX = 0; $0.lookX = 1 }
        let mid = P { $0.armRY = -1; $0.armRX = -2; $0.lookX = 1 }
        let hit = P { $0.armRY = 4; $0.armRX = -2; $0.lookX = 1; $0.lookY = 1; $0.squash = 1 }
        c["build"] = ClipData(keys: [K(8, up), K(1, mid), K(4, hit, cut: true), K(2, mid), K(8, up), K(1, mid), K(4, hit, cut: true), K(2, mid)], held: true, maxDelta: 130)

        // Points at a branch graph that grows a commit and merges it.
        let point = P { $0.armRY = -9; $0.armRX = -1; $0.lookX = 1; $0.lookY = -1 }
        c["git"] = ClipData(keys: [K(18, point), K(2, point.with { $0.lift = 1 }), K(16, point)])

        // A parcel drops into the box in Wigglet's hands, the box shakes while it installs, then opens with a check.
        let catchBox = P { $0.armLX = 4; $0.armLY = 5; $0.armRX = 4; $0.armRY = 5 }
        c["install"] = ClipData(keys: [
            K(8, catchBox.with { $0.lookY = -1 }), K(2, catchBox.with { $0.squash = 1 }), K(2, catchBox),
            K(2, catchBox.with { $0.lean = -1; $0.eyes = .closed }), K(2, catchBox.with { $0.lean = 1; $0.eyes = .closed }),
            K(2, catchBox.with { $0.lean = -1; $0.eyes = .closed }), K(2, catchBox.with { $0.lean = 1; $0.eyes = .closed }),
            K(4, catchBox), K(16, catchBox.with { $0.eyes = .happy; $0.mouth = .smile })], held: true)

        // Holds a rocket up, counts down, launches it and cheers.
        let rocket = P { $0.armRY = -9; $0.armRX = 0; $0.lookX = 1; $0.lookY = -1 }
        let shade = P { $0.armRX = 5; $0.armRY = -3; $0.lookY = -1; $0.lookX = 1; $0.mouth = .smile }
        c["deploy"] = ClipData(keys: [
            K(12, rocket), K(24, armsUp.with { $0.eyes = .happy; $0.mouth = .open; $0.lookY = -1 }, cut: true),
            K(24, shade), K(1, shade.with { $0.eyes = .closed }), K(11, shade)], loops: false, loopFrom: 36)

        // Throws a paper plane up and to the right.
        c["push"] = ClipData(keys: [
            K(8, P { $0.armRY = 0; $0.armRX = -2; $0.lookX = 1 }), K(2, P { $0.armRY = -8; $0.armRX = 1; $0.lookX = 1 }, cut: true),
            K(18, P { $0.armRY = -6; $0.armRX = 0; $0.lookX = 1; $0.lookY = -1; $0.mouth = .smile }), K(8, Pose())])

        // A parcel floats down on a parachute into the hands.
        c["pull"] = ClipData(keys: [
            K(24, holdFront.with { $0.lookY = -1 }), K(2, holdFront.with { $0.squash = 1 }, cut: true),
            K(14, holdFront.with { $0.eyes = .happy; $0.mouth = .smile })], maxDelta: 170)

        // Magnifier over a small globe.
        c["webSearch"] = ClipData(keys: [
            K(8, lens.with { $0.armRX = 8; $0.armRY = 2 }), K(8, lens.with { $0.armRX = 4; $0.armRY = 2 }), K(8, lens.with { $0.armRX = 6; $0.armRY = 1; $0.eyes = .tall })], held: true)

        // Hand on chin, eyes wander; a light bulb at the end.
        c["think"] = ClipData(keys: [
            K(10, chin.with { $0.lookX = 1 }), K(4, chin), K(10, chin.with { $0.lookX = -1 }), K(1, chin.with { $0.eyes = .closed }),
            K(3, chin.with { $0.lookX = 1 }), K(8, P { $0.eyes = .tall; $0.mouth = .o; $0.lookY = -1; $0.armRY = -7; $0.armRX = -1 })])

        // Wipes the brow, then pumps both fists: still going.
        var grind: [Key] = [K(3), K(2, P { $0.armRY = -5; $0.armRX = 2 }), K(2, P { $0.armRY = -5; $0.armRX = 7; $0.eyes = .closed }),
                            K(3, P { $0.armRY = -5; $0.armRX = 12; $0.eyes = .closed }), K(2, P { $0.armRY = -2; $0.armRX = 4 }), K(2)]
        for i in 0..<4 { grind.append(K(4, P { $0.eyes = .closed; $0.mouth = .flat; if i % 2 == 0 { $0.armLY = -8 } else { $0.armRY = -8 } })) }
        grind.append(K(6, P { $0.mouth = .smile }))
        c["grind"] = ClipData(keys: grind, loops: false)

        // Typing at full speed.
        var frantic: [Key] = []
        for i in 0..<12 { frantic.append(K(1, desk.with { $0.eyes = .tall; $0.lookY = 0; $0.armLY = i % 2 == 0 ? 4 : 6; $0.armRY = i % 2 == 0 ? 6 : 4 }, cut: i > 0)) }
        c["frantic"] = ClipData(keys: frantic, maxDelta: 140)

        // Waiting on a slow tool: eyes dart, a foot taps, sweat runs.
        let nervous = P { $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 1; $0.mouth = .wavy }
        c["sweat"] = ClipData(keys: [
            K(3, nervous.with { $0.lookX = -1 }), K(3, nervous.with { $0.lookX = -1; $0.leg = [0, 0, 0, 2] }),
            K(3, nervous.with { $0.lookX = 1 }), K(3, nervous.with { $0.lookX = 1; $0.leg = [0, 0, 0, 2] }),
            K(3, nervous.with { $0.lookX = -1 }), K(3, nervous.with { $0.lookX = -1; $0.leg = [0, 0, 0, 2] }),
            K(3, nervous.with { $0.lookX = 1 }), K(3, nervous.with { $0.lookX = 1; $0.leg = [0, 0, 0, 2] })])

        // A cup of tea: hold, sip with eyes closed, a content sigh.
        let mug = P { $0.armRX = 6; $0.armRY = 3; $0.armLX = 4; $0.armLY = 4 }
        c["tea"] = ClipData(keys: [
            K(14, mug), K(10, mug.with { $0.armRY = -1; $0.armLY = 0; $0.eyes = .closed }),
            K(12, mug.with { $0.eyes = .happy; $0.mouth = .smile }), K(1, mug.with { $0.eyes = .closed }), K(11, mug)], held: true)

        // Checks a wristwatch, looks at you, sighs.
        let wrist = P { $0.armLX = 6; $0.armLY = 3; $0.lookX = -1; $0.lookY = 1 }
        c["watch"] = ClipData(keys: [
            K(12, wrist), K(6, P { $0.leg = [0, 0, 0, 2] }), K(6, P { $0.mouth = .flat }),
            K(12, P { $0.squash = 1; $0.eyes = .closed; $0.mouth = .flat })])

        // Waves a flag overhead to get attention.
        let flag = P { $0.armRY = -9; $0.armRX = 3; $0.mouth = .open; $0.eyes = .tall }
        c["flag"] = ClipData(keys: [
            K(6, flag), K(6, flag.with { $0.armRX = 1; $0.lift = 1 }), K(6, flag), K(6, flag.with { $0.armRX = 5; $0.lift = 1 })],
            held: true, airborne: true)

        // ---------- waiting ----------
        let raise = P { $0.armRY = -10; $0.armRX = 1; $0.eyes = .tall; $0.mouth = .o }
        c["ask"] = ClipData(keys: [
            K(3, raise), K(3, raise.with { $0.armRX = 3 }), K(3, raise.with { $0.lift = 1 }), K(3, raise.with { $0.armRX = 3; $0.lift = 1 }),
            K(3, raise), K(3, raise.with { $0.armRX = 3 }), K(6, raise.with { $0.eyes = .open })], airborne: true)

        // ---------- events ----------
        c["done"] = ClipData(keys: [
            K(3, P { $0.squash = 2 }), K(1, armsUp.with { $0.lift = 3; $0.eyes = .happy; $0.mouth = .open }),
            K(4, armsUp.with { $0.lift = 7; $0.eyes = .happy; $0.mouth = .open }), K(1, armsUp.with { $0.lift = 4; $0.eyes = .happy }),
            K(2, happy.with { $0.squash = 2 }), K(13, happy.with { $0.armLY = -5; $0.armRY = -5 })], airborne: true, loops: false)

        let shock = P { $0.eyes = .tall; $0.mouth = .o; $0.armLY = -3; $0.armRY = -3; $0.lean = -2 }
        c["oops"] = ClipData(keys: [
            K(2, shock, cut: true), K(6, shock.with { $0.lean = 0 }),
            K(10, P { $0.armRX = 6; $0.armRY = -9; $0.eyes = .closed; $0.mouth = .wavy }), K(6, P { $0.mouth = .wavy })])

        c["hello"] = ClipData(keys: [
            K(2, P { $0.fade = 3; $0.lift = 2 }, cut: true), K(2, P { $0.fade = 2; $0.lift = 1 }), K(2, P { $0.fade = 1 }),
            K(2, P { $0.squash = 1 })] + wave(happy, cycles: 2) + [K(4, happy)], airborne: true, maxDelta: 400, loops: false)

        c["bye"] = ClipData(keys: wave(happy, cycles: 2) + [
            K(3, happy.with { $0.fade = 1 }, cut: true), K(3, happy.with { $0.fade = 2 }, cut: true),
            K(3, P { $0.fade = 3 }, cut: true), K(3, P { $0.fade = 4 }, cut: true)], loops: false)

        let tubeUp = P { $0.armRY = -3; $0.armRX = 2; $0.lookX = 1; $0.lookY = -1 }
        c["testPass"] = ClipData(keys: [
            K(8, tubeUp), K(2, tubeUp.with { $0.squash = 2; $0.eyes = .happy }),
            K(2, tubeUp.with { $0.lift = 4; $0.armLY = -9; $0.eyes = .happy; $0.mouth = .open }),
            K(2, tubeUp.with { $0.lift = 6; $0.armLY = -9; $0.eyes = .happy; $0.mouth = .open }),
            K(2, tubeUp.with { $0.lift = 3; $0.eyes = .happy }), K(2, tubeUp.with { $0.squash = 1; $0.eyes = .happy }),
            K(12, tubeUp.with { $0.eyes = .happy; $0.mouth = .smile })], held: true, airborne: true, loops: false)
        c["testFail"] = ClipData(keys: [
            K(6, tubeUp), K(4, tubeUp.with { $0.eyes = .tall; $0.mouth = .o; $0.lean = -1 }),
            K(14, P { $0.armRX = 3; $0.armRY = 4; $0.squash = 2; $0.eyes = .closed; $0.mouth = .flat })], held: true, loops: false)

        // Hands a parcel to a helper, who carries it off; then waves.
        c["handoff"] = ClipData(keys: [
            K(8, holdFront.with { $0.lookX = 1 }), K(6, P { $0.armRX = 0; $0.armRY = 1; $0.lookX = 1 }),
            K(4, P { $0.lookX = 1; $0.mouth = .smile }), K(12, happy.with { $0.armRY = -9; $0.armRX = -1 })], maxDelta: 150, loops: false)

        // Two pages crash together.
        let pages = P { $0.armLY = -4; $0.armRY = -4; $0.armLX = -1; $0.armRX = -1 }
        c["conflict"] = ClipData(keys: [
            K(4, pages), K(3, pages.with { $0.armLX = 3; $0.armRX = 3 }), K(3, pages.with { $0.armLX = 6; $0.armRX = 6 }),
            K(14, pages.with { $0.armLX = 6; $0.armRX = 6; $0.eyes = .cross; $0.mouth = .wavy; $0.squash = 1 })], held: true, maxDelta: 150, loops: false)

        c["confetti"] = ClipData(keys: [
            K(6, P { $0.armRY = -7; $0.armRX = 0; $0.lookX = 1; $0.lookY = -1 }),
            K(18, armsUp.with { $0.eyes = .happy; $0.mouth = .open; $0.lift = 1 }, cut: true)], airborne: true, loops: false)

        // ---------- ambient ----------
        c["breathe"] = ClipData(keys: [K(18), K(10, P { $0.squash = 1 }), K(14), K(1, blink), K(5)])
        c["glance"] = ClipData(keys: [
            K(8), K(4, P { $0.lookX = -2 }), K(10, P { $0.profile = .left }), K(4, P { $0.lookX = -2 }),
            K(6), K(4, P { $0.lookX = 2 }), K(10, P { $0.profile = .right }), K(4, P { $0.lookX = 2 })])
        c["stretch"] = ClipData(keys: [
            K(3, P { $0.squash = 1 }), K(14, armsUp.with { $0.lift = 1; $0.eyes = .closed; $0.mouth = .o; $0.armLX = 0; $0.armRX = 0 }),
            K(3, armsUp.with { $0.lift = 2; $0.eyes = .closed; $0.mouth = .o; $0.armLX = -1; $0.armRX = -1 }), K(10)], airborne: true)
        c["yawn"] = ClipData(keys: [
            K(4), K(3, P { $0.eyes = .closed; $0.mouth = .o; $0.armLY = -2; $0.armRY = -2 }),
            K(12, P { $0.eyes = .closed; $0.mouth = .yawn; $0.armLY = -6; $0.armRY = -6; $0.armLX = -1; $0.armRX = -1 }),
            K(3, P { $0.eyes = .closed; $0.mouth = .o }), K(4), K(1, blink), K(9)])
        c["dance"] = ClipData(keys: [
            K(3, happy.with { $0.lean = -2; $0.armLY = -7; $0.armRY = 2; $0.leg = [0, 0, 0, 2] }), K(3, happy),
            K(3, happy.with { $0.lean = 2; $0.armLY = 2; $0.armRY = -7; $0.leg = [2, 0, 0, 0] }), K(3, happy),
            K(3, happy.with { $0.lean = -2; $0.armLY = -7; $0.armRY = 2; $0.leg = [0, 0, 0, 2] }), K(3, happy),
            K(3, happy.with { $0.lean = 2; $0.armLY = 2; $0.armRY = -7; $0.leg = [2, 0, 0, 0] }), K(3, happy)])
        let hum = P { $0.eyes = .closed; $0.mouth = .o }
        c["hum"] = ClipData(keys: [K(12, hum.with { $0.lean = -1 }), K(12, hum), K(12, hum.with { $0.lean = 1 }), K(12, hum)])
        c["juggle"] = ClipData(keys: [
            K(4, P { $0.armLY = -4; $0.armRY = 1; $0.lookY = -1 }), K(4, P { $0.armLY = 1; $0.armRY = -4; $0.lookY = -1 }),
            K(4, P { $0.armLY = -4; $0.armRY = 1; $0.lookY = -1 }), K(4, P { $0.armLY = 1; $0.armRY = -4; $0.lookY = -1 }),
            K(4, P { $0.armLY = -4; $0.armRY = 1; $0.lookY = -1 }), K(4, P { $0.armLY = 1; $0.armRY = -4; $0.lookY = -1 })])
        let dream = P { $0.squash = 2; $0.eyes = .closed; $0.mouth = .smile; $0.armLY = 1; $0.armRY = 1 }
        c["dream"] = ClipData(keys: [K(24, dream), K(24, dream.with { $0.squash = 3 })])

        // ---------- sleep ----------
        let sleep = P { $0.squash = 3; $0.eyes = .closed; $0.armLY = 2; $0.armRY = 2 }
        c["sleep"] = ClipData(keys: [K(24, sleep), K(24, sleep.with { $0.squash = 4 })])
        let sit = P { $0.crouch = true; $0.armLX = 4; $0.armLY = 4; $0.armRX = 4; $0.armRY = 4 }
        c["nightcap"] = ClipData(keys: [K(20, sit.with { $0.eyes = .closed }), K(4, sit.with { $0.lookY = -1 }), K(24, sit.with { $0.eyes = .closed })], held: true)
        let doze = P { $0.crouch = true; $0.eyes = .closed; $0.armLY = 2; $0.armRY = 2 }
        c["nap"] = ClipData(keys: [K(12, doze), K(6, doze.with { $0.squash = 2 }), K(4, doze), K(14, doze.with { $0.squash = 2 })])

        // ---------- interaction ----------
        let dangle = P { $0.armLY = -9; $0.armRY = -9; $0.eyes = .tall; $0.mouth = .o }
        c["drag"] = ClipData(keys: [K(3, dangle.with { $0.leg = [0, 2, 0, 2] }), K(3, dangle.with { $0.leg = [2, 0, 2, 0] })], airborne: true)
        let pet = P { $0.eyes = .happy; $0.mouth = .smile; $0.blush = true }
        c["pet"] = ClipData(keys: [K(6, pet.with { $0.lean = -1 }), K(6, pet), K(6, pet.with { $0.lean = 1 }), K(6, pet)])
        let ear = P { $0.armRY = -5; $0.armRX = -1; $0.lookX = 1; $0.lean = 1 }
        c["listen"] = ClipData(keys: [K(6, ear), K(6, ear.with { $0.lift = 1 }), K(6, ear), K(1, ear.with { $0.eyes = .closed }), K(5, ear)], airborne: true)
        c["chatThink"] = ClipData(keys: [K(10, chin.with { $0.lookX = 1 }), K(2, chin), K(10, chin.with { $0.lookX = -1 }), K(1, chin.with { $0.eyes = .closed }), K(1, chin)])
        let talk = P { $0.armRX = 3; $0.armRY = 1 }
        c["chatTalk"] = ClipData(keys: [
            K(2, talk.with { $0.mouth = .open }), K(2, talk.with { $0.mouth = .flat }), K(2, talk.with { $0.mouth = .open; $0.armRY = -3 }),
            K(2, talk.with { $0.mouth = .o; $0.armRY = -3 }), K(2, talk.with { $0.mouth = .open }), K(2, talk.with { $0.mouth = .smile }),
            K(2, talk.with { $0.mouth = .open; $0.armRY = -2 }), K(1, talk.with { $0.mouth = .flat; $0.eyes = .closed }), K(1, talk.with { $0.mouth = .flat })])
        let woozy = P { $0.eyes = .spiral; $0.mouth = .wavy }
        c["dizzy"] = ClipData(keys: [
            K(3, woozy.with { $0.lean = -2 }), K(3, woozy), K(3, woozy.with { $0.lean = 2 }), K(3, woozy),
            K(3, woozy.with { $0.lean = -2 }), K(3, woozy), K(3, woozy.with { $0.lean = 2 }), K(9, woozy)], loops: false)

        // ---------- team ----------
        c["hop"] = ClipData(keys: [
            K(2, happy.with { $0.squash = 2 }), K(1, happy.with { $0.lift = 3; $0.armLY = -5; $0.armRY = -5 }),
            K(3, happy.with { $0.lift = 6; $0.armLY = -9; $0.armRY = -9 }), K(1, happy.with { $0.lift = 3 }),
            K(2, happy.with { $0.squash = 2 }), K(3, happy)], airborne: true)
        c["wave"] = ClipData(keys: wave(happy.with { $0.lookX = 1 }, cycles: 3), loops: false)
        c["highFive"] = ClipData(keys: [
            K(4, P { $0.armRY = -6; $0.armRX = -2; $0.lookX = 1 }), K(2, happy.with { $0.armRY = -8; $0.armRX = -4; $0.lookX = 1 }, cut: true),
            K(12, happy.with { $0.armRY = -8; $0.armRX = -3; $0.lookX = 1 })], loops: false)
        c["parcel"] = ClipData(keys: [
            K(8, holdFront.with { $0.lookX = 1 }), K(4, P { $0.armRX = 0; $0.armRY = -4; $0.lookX = 1; $0.lookY = -1 }),
            K(6, P { $0.lookX = 1 }), K(6, happy.with { $0.armRY = -9; $0.armRX = -1 })], maxDelta: 150, loops: false)

        // ---------- chat problems ----------
        c["offline"] = ClipData(keys: [
            K(10, P { $0.armRX = 5; $0.armRY = 3; $0.lookX = 1; $0.lookY = 1; $0.mouth = .flat }),
            K(4, P { $0.armRX = 5; $0.armRY = 1; $0.armLY = -2; $0.mouth = .flat }),
            K(10, P { $0.armRX = 5; $0.armRY = 3; $0.lookX = 1; $0.lookY = 1; $0.mouth = .wavy })], held: true)
        let crossed = P { $0.armLX = 7; $0.armLY = 4; $0.armRX = 7; $0.armRY = 3; $0.mouth = .flat; $0.lookY = -1 }
        c["rateLimited"] = ClipData(keys: [
            K(3, crossed), K(3, crossed.with { $0.leg = [0, 0, 0, 2] }), K(3, crossed), K(3, crossed.with { $0.leg = [0, 0, 0, 2] }),
            K(3, crossed), K(3, crossed.with { $0.leg = [0, 0, 0, 2] }), K(3, crossed.with { $0.lookY = 0 }), K(3, crossed.with { $0.lookY = 0; $0.eyes = .closed })])
        c["timeout"] = ClipData(keys: [
            K(6, P { $0.lookX = -1; $0.lookY = -1 }), K(6, P { $0.lookX = 1; $0.lookY = -1 }),
            K(6, P { $0.lookX = -1; $0.lookY = -1 }), K(6, P { $0.lookX = 1; $0.lookY = -1 }),
            K(12, P { $0.squash = 2; $0.eyes = .closed; $0.mouth = .wavy; $0.armLY = 2; $0.armRY = 2 })])
        let jar = P { $0.armLX = 4; $0.armLY = 3; $0.armRX = 4; $0.armRY = 3; $0.lookY = 1 }
        c["outOfCredits"] = ClipData(keys: [
            K(6, jar), K(2, jar.with { $0.armLY = 0; $0.armRY = 0; $0.lean = -1 }), K(2, jar.with { $0.armLY = 2; $0.armRY = 2; $0.lean = 1 }),
            K(2, jar.with { $0.armLY = 0; $0.armRY = 0; $0.lean = -1 }), K(2, jar.with { $0.armLY = 2; $0.armRY = 2; $0.lean = 1 }),
            K(16, jar.with { $0.eyes = .closed; $0.mouth = .flat; $0.squash = 1 })], held: true)
        return c
    }()

    /// Expanded frames per clip, built once.
    static let frames: [String: [Pose]] = clips.mapValues { $0.frames }
}
