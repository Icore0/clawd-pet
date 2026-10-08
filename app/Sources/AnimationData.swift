import Foundation

// Hand-authored frame data for every clip. Pure data: integer cell poses and holds at 12 fps.
// The 2D renderer reads it today; a voxel renderer can read the same lists later.
//
// Conventions (sprite cells, y grows down):
//  armLY/armRY -3...+3 move a hand up/down one cell per step; armLX/armRX > 0 bring a hand in front of the body.
//  A hand never moves away from the body (armX < 0), so limbs stay attached.
//  `hold` is how many 12 fps frames a key stays on screen. `cut` marks an intended jump the frame audit allows.

struct Key {
    var pose: Pose
    var hold: Int
    var cut = false
}

struct ClipData {
    var keys: [Key]
    /// A prop in this clip is carried: it must touch a hand in every frame.
    var held = false
    /// Frames may leave the ground or fling a limb (jumps, throws).
    var airborne = false
    /// Max changed cells between two adjacent frames (shape only; translation is checked separately).
    var maxDelta = 20

    var frameCount: Int { keys.reduce(0) { $0 + $1.hold } }

    func index(_ frame: Int, loop: Bool) -> Int {
        let n = max(1, frameCount)
        return loop ? ((frame % n) + n) % n : min(max(0, frame), n - 1)
    }

    func key(at frame: Int, loop: Bool) -> Key {
        var f = index(frame, loop: loop)
        for k in keys {
            if f < k.hold { return k }
            f -= k.hold
        }
        return keys[keys.count - 1]
    }

    /// Frame index where each key starts, for the audit.
    var starts: [Int] {
        var out: [Int] = [], acc = 0
        for k in keys { out.append(acc); acc += k.hold }
        return out
    }
}

private let rest = Pose()
private func K(_ hold: Int, _ p: Pose = Pose(), cut: Bool = false) -> Key { Key(pose: p, hold: hold, cut: cut) }
private func P(_ f: (inout Pose) -> Void) -> Pose { Pose().with(f) }

enum AnimationData {
    // MARK: shared building blocks
    private static let blink = P { $0.eyes = .dash }
    private static let armsUp1 = P { $0.armLY = -1; $0.armRY = -1 }
    private static let armsUp2 = P { $0.armLY = -2; $0.armRY = -2 }
    private static let hold2 = P { $0.armLX = 1; $0.armLY = 1; $0.armRX = 1; $0.armRY = 1 }   // both hands in front, carrying
    private static let rightHold = P { $0.armRX = 1; $0.armRY = 0 }                          // one hand forward
    private static let squash = P { $0.squash = 1 }

    private static func typing(_ base: Pose, beats: Int, glanceUp: Bool) -> [Key] {
        var keys: [Key] = []
        for i in 0..<beats {
            keys.append(K(2, base.with { $0.armLX = 1; $0.armRX = 1; $0.armLY = i % 2 == 0 ? 2 : 1; $0.armRY = i % 2 == 0 ? 1 : 2; $0.lookY = 1 }))
        }
        if glanceUp {
            keys.append(K(4, base.with { $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 1; $0.lookY = 0 }))
            keys.append(K(1, base.with { $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 1; $0.eyes = .dash }))
            keys.append(K(2, base.with { $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 1; $0.lookY = 1 }))
        }
        return keys
    }

    private static func sleeping(_ extra: (inout Pose) -> Void = { _ in }) -> [Key] {
        [K(16, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1; extra(&$0) }),
         K(16, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1; $0.squash = 1; extra(&$0) })]
    }

    private static func slump(_ look: Int) -> [Key] {
        [K(10, P { $0.squash = 1; $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1 }),
         K(10, P { $0.squash = 1; $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1; $0.lookX = look })]
    }

    private static func waveRight(_ cycles: Int, base: Pose = Pose()) -> [Key] {
        var keys = [K(2, base.with { $0.armRY = -2 })]
        for _ in 0..<cycles { keys += [K(3, base.with { $0.armRY = -3 }), K(3, base.with { $0.armRY = -2 })] }
        return keys
    }

    private static func thinking(_ base: Pose = Pose()) -> [Key] {
        let chin = base.with { $0.eyes = .tall; $0.armRX = 1; $0.armRY = 1 }
        return [K(8, chin.with { $0.lookX = 1; $0.lookY = -1 }), K(3, chin.with { $0.lookY = -1 }),
                K(8, chin.with { $0.lookX = -1; $0.lookY = -1 }), K(1, chin.with { $0.eyes = .dash }), K(4, chin)]
    }

    // MARK: clips
    static let clips: [String: ClipData] = {
        var c: [String: ClipData] = [:]

        // Ambient idles: long holds, one change at a time, so a resting Clawd never loops visibly.
        c["breathe"] = ClipData(keys: [K(14), K(4, armsUp1), K(2), K(16), K(1, blink), K(3)])
        c["blink"] = ClipData(keys: [K(12), K(1, blink), K(2), K(1, blink), K(10)])
        c["glance"] = ClipData(keys: [
            K(6), K(2, P { $0.lookX = 1 }), K(10, P { $0.profile = .right }), K(2, P { $0.lookX = 1 }),
            K(6), K(2, P { $0.lookX = -1 }), K(10, P { $0.profile = .left }), K(2, P { $0.lookX = -1 })])
        c["stretch"] = ClipData(keys: [
            K(3, squash), K(2, armsUp1), K(10, armsUp2.with { $0.lift = 1; $0.eyes = .dash }),
            K(2, armsUp2.with { $0.armLY = -3; $0.armRY = -3; $0.lift = 1; $0.eyes = .dash }), K(2, armsUp1), K(6)], airborne: true)
        c["grind"] = ClipData(keys: [
            K(4), K(3, squash), K(2, armsUp1), K(12, armsUp2.with { $0.lift = 1; $0.eyes = .dash }),
            K(3, armsUp1), K(4, P { $0.lean = -1; $0.lookX = -1 }), K(1), K(4, P { $0.lean = 1; $0.lookX = 1 }), K(4)], airborne: true)
        c["yawn"] = ClipData(keys: [
            K(4), K(3, P { $0.eyes = .dash; $0.armLY = -1; $0.armRY = -1 }),
            K(10, P { $0.eyes = .tall; $0.armLY = -2; $0.armRY = -2; $0.lookY = -1 }),
            K(3, P { $0.eyes = .dash; $0.armLY = -1; $0.armRY = -1 }), K(4), K(1, blink), K(5)])
        c["dance"] = ClipData(keys: [
            K(3, P { $0.lean = -1; $0.armLY = -2; $0.armRY = 1; $0.leg = [0, 0, 0, 1] }), K(2),
            K(3, P { $0.lean = 1; $0.armLY = 1; $0.armRY = -2; $0.leg = [1, 0, 0, 0] }), K(2)])
        c["hum"] = ClipData(keys: [K(5), K(3, P { $0.lift = 1; $0.eyes = .dash }), K(5), K(3, P { $0.lift = 1 })], airborne: true)
        c["mote"] = ClipData(keys: [
            K(6, P { $0.lookX = -1; $0.lookY = -1 }), K(4, P { $0.lookY = -1 }), K(6, P { $0.lookX = 1; $0.lookY = -1 }),
            K(3, P { $0.lookX = 1; $0.lookY = -1; $0.armRY = -1 }), K(5, P { $0.lookX = 1 })])
        c["juggle"] = ClipData(keys: [K(3, P { $0.armLY = -1; $0.lookY = -1 }), K(3, P { $0.armRY = -1; $0.lookY = -1 })])
        c["dream"] = ClipData(keys: [K(12, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1 }), K(8, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1; $0.squash = 1 })])
        c["sleep"] = ClipData(keys: sleeping())
        c["nap"] = ClipData(keys: sleeping())
        c["nightcap"] = ClipData(keys: sleeping())
        c["think"] = ClipData(keys: thinking())
        c["thinking"] = ClipData(keys: thinking())
        c["chatThink"] = ClipData(keys: thinking())

        // Work. Props are carried by a hand and drawn from it.
        c["read"] = ClipData(keys: [
            K(6, hold2.with { $0.lookY = 1; $0.lookX = -1 }), K(6, hold2.with { $0.lookY = 1 }),
            K(6, hold2.with { $0.lookY = 1; $0.lookX = 1 }), K(1, hold2.with { $0.lookY = 1; $0.eyes = .dash }),
            K(3, hold2.with { $0.lookY = 1; $0.lookX = 1; $0.armRY = 0 })], held: true)
        c["burstRead"] = ClipData(keys: [
            K(2, hold2.with { $0.lookY = 1; $0.lookX = -1 }), K(2, hold2.with { $0.lookY = 1; $0.lookX = 1 }),
            K(2, hold2.with { $0.lookY = 1; $0.lookX = 1; $0.armRY = 0 })], held: true)
        c["book"] = ClipData(keys: [
            K(10, hold2.with { $0.lookY = 1; $0.lookX = -1 }), K(10, hold2.with { $0.lookY = 1; $0.lookX = 1 }),
            K(1, hold2.with { $0.lookY = 1; $0.eyes = .dash }), K(4, hold2.with { $0.lookY = 1; $0.armRY = 0 })], held: true)
        c["notebook"] = ClipData(keys: [
            K(6, hold2.with { $0.lookY = 1 }), K(2, hold2.with { $0.lookY = 1; $0.armRY = 2 }), K(2, hold2.with { $0.lookY = 1 }),
            K(2, hold2.with { $0.lookY = 1; $0.armRY = 2 }), K(6, hold2.with { $0.lookY = 1; $0.lookX = 1 })], held: true)
        c["edit"] = ClipData(keys: typing(P { $0.crouch = true }, beats: 8, glanceUp: true))
        c["bash"] = ClipData(keys: typing(P { $0.crouch = true }, beats: 6, glanceUp: true) + [K(3, P { $0.crouch = true; $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 1; $0.lookY = 1; $0.lookX = 1 })])
        c["frantic"] = ClipData(keys: [
            K(1, P { $0.crouch = true; $0.armLX = 1; $0.armRX = 1; $0.armLY = 2; $0.armRY = 1; $0.lookY = 1; $0.eyes = .tall }),
            K(1, P { $0.crouch = true; $0.armLX = 1; $0.armRX = 1; $0.armLY = 1; $0.armRY = 2; $0.lookY = 1; $0.eyes = .tall })])
        let lens = P { $0.armRY = 1 }
        c["search"] = ClipData(keys: [
            K(4, lens.with { $0.lookX = 1; $0.profile = .right }), K(2, lens.with { $0.armRX = 1; $0.lookX = 1 }),
            K(3, lens.with { $0.armRX = 2 }), K(2, lens.with { $0.armRX = 3; $0.lookX = -1 }),
            K(4, lens.with { $0.armRX = 3; $0.lookX = -1; $0.profile = .left }), K(2, lens.with { $0.armRX = 2; $0.lookX = -1 }),
            K(3, lens.with { $0.armRX = 1 })], held: true)
        c["webSearch"] = ClipData(keys: [
            K(5, lens.with { $0.armRX = 1; $0.lookX = 1 }), K(3, lens.with { $0.armRX = 2 }),
            K(5, lens.with { $0.armRX = 3; $0.lookX = -1 }), K(3, lens.with { $0.armRX = 2 })], held: true)
        c["web"] = ClipData(keys: [K(6, hold2.with { $0.lookY = -1 }), K(3, hold2.with { $0.lookY = -1; $0.lift = 1 }), K(6, hold2.with { $0.lookY = -1 }), K(1, hold2.with { $0.eyes = .dash })], held: true, airborne: true)
        c["webFetch"] = ClipData(keys: [
            K(8, rightHold.with { $0.lookX = 1; $0.lookY = 1 }), K(2, rightHold.with { $0.lookY = 1 }),
            K(8, rightHold.with { $0.lookX = 1; $0.lookY = 1; $0.armRY = -1 }), K(1, rightHold.with { $0.eyes = .dash })], held: true)
        c["plan"] = ClipData(keys: [
            K(6, hold2.with { $0.lookY = 1; $0.lookX = -1 }), K(5, hold2.with { $0.lookY = 1 }),
            K(2, hold2.with { $0.lookY = 1; $0.armRY = 0 }), K(5, hold2.with { $0.lookY = 1; $0.lookX = 1 })], held: true)
        c["compact"] = ClipData(keys: [
            K(4, P { $0.armLX = 1; $0.armRX = 1; $0.eyes = .dash }), K(4, P { $0.armLX = 2; $0.armRX = 2; $0.squash = 1; $0.eyes = .dash }),
            K(2, P { $0.armLX = 1; $0.armRX = 1; $0.squash = 1; $0.eyes = .dash }), K(3)])
        c["test"] = ClipData(keys: [
            K(5, rightHold.with { $0.lookX = 1; $0.eyes = .tall }), K(2, rightHold.with { $0.armRY = -1; $0.lookX = 1 }),
            K(2, rightHold.with { $0.lookX = 1 }), K(2, rightHold.with { $0.armRY = -1; $0.lookX = 1 }),
            K(6, rightHold.with { $0.lookX = 1; $0.eyes = .tall }), K(1, rightHold.with { $0.eyes = .dash })], held: true)
        c["testPass"] = ClipData(keys: [
            K(2, squash), K(3, armsUp1.with { $0.lift = 1 }), K(10, armsUp2.with { $0.lift = 1; $0.blush = true }),
            K(3, armsUp1.with { $0.blush = true }), K(8, P { $0.blush = true })], airborne: true)
        c["testFail"] = ClipData(keys: [
            K(2, P { $0.dx = -1; $0.eyes = .cross }), K(2, P { $0.dx = 0; $0.eyes = .cross }), K(2, P { $0.dx = 1; $0.eyes = .cross }),
            K(2, P { $0.dx = 0; $0.eyes = .cross }), K(10, P { $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }), K(6, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1 })])
        c["build"] = ClipData(keys: [
            K(3, P { $0.armRY = -2; $0.lookX = 1; $0.lookY = 1 }), K(2, P { $0.armRY = -1; $0.lookX = 1; $0.lookY = 1 }),
            K(1, P { $0.armRY = 0; $0.lookX = 1; $0.lookY = 1 }),
            K(2, P { $0.armRY = 1; $0.lookX = 1; $0.lookY = 1; $0.eyes = .dash; $0.squash = 1 }), K(4, P { $0.armRY = 0; $0.lookX = 1; $0.lookY = 1 }),
            K(1, P { $0.armRY = -1; $0.lookX = 1; $0.lookY = 1 })], held: true, maxDelta: 26)
        c["git"] = ClipData(keys: [
            K(8, P { $0.armRY = -1; $0.lookX = 1; $0.profile = .right }), K(2, P { $0.armRY = -2; $0.lookX = 1; $0.profile = .right }),
            K(6, P { $0.armRY = -1; $0.lookX = 1; $0.profile = .right }), K(2, P { $0.lookX = 1 }), K(1, blink), K(3, P { $0.lookX = 1 })])
        let catchArms = P { $0.armLX = 1; $0.armRX = 1; $0.armLY = -1; $0.armRY = -1; $0.lookY = -1 }
        c["install"] = ClipData(keys: [K(5, catchArms, cut: true), K(2, catchArms.with { $0.squash = 1 }), K(5, catchArms), K(2, catchArms.with { $0.squash = 1 }), K(5, catchArms), K(2, catchArms.with { $0.squash = 1 }), K(8, catchArms.with { $0.lookY = 0 })], held: true)
        c["migrate"] = ClipData(keys: [K(3, hold2.with { $0.leg = [1, 0, 1, 0] }), K(3, hold2.with { $0.leg = [0, 1, 0, 1] })], held: true)
        c["docker"] = ClipData(keys: [K(6, hold2), K(3, hold2.with { $0.lift = 1 }), K(6, hold2), K(1, hold2.with { $0.eyes = .dash })], held: true, airborne: true)
        c["pull"] = ClipData(keys: [K(4, P { $0.armLX = 1; $0.armRX = 1; $0.armLY = -1; $0.armRY = -1; $0.lookY = -1 }), K(2, P { $0.armLX = 1; $0.armRX = 1 }), K(4, hold2), K(8, hold2.with { $0.blush = true }), K(4, hold2), K(2, P { $0.armLX = 1; $0.armRX = 1 })], held: true)
        c["lint"] = ClipData(keys: [K(3, rightHold), K(3, rightHold.with { $0.armRX = 2 }), K(3, rightHold.with { $0.armRX = 3; $0.lookX = -1 }), K(3, rightHold.with { $0.armRX = 2 })], held: true)
        c["serve"] = ClipData(keys: [K(10, P { $0.armRY = -2; $0.lookX = 1; $0.lookY = -1 }), K(1, P { $0.armRY = -2; $0.eyes = .dash }), K(8, P { $0.armRY = -2; $0.lookX = 1; $0.lookY = -1 })], held: true)
        c["mcp"] = ClipData(keys: [K(6, rightHold.with { $0.armRY = 1; $0.lookX = 1; $0.lookY = 1 }), K(2, rightHold.with { $0.armRY = 2; $0.lookX = 1; $0.lookY = 1 }), K(4, rightHold.with { $0.armRY = 1; $0.lookX = 1 })], held: true)
        c["commit"] = ClipData(keys: [K(4, P { $0.armRY = -2; $0.lookY = 1 }), K(2, P { $0.armRY = -1; $0.lookY = 1 }), K(1, P { $0.armRY = 0; $0.lookY = 1 }), K(6, P { $0.armRY = 1; $0.lookY = 1; $0.squash = 1 }), K(4, P { $0.armRY = 0; $0.lookY = 1 }), K(2, P { $0.armRY = -1; $0.lookY = 1 })], held: true)
        c["deploy"] = ClipData(keys: [
            K(4, P { $0.armRY = -1; $0.lookX = 1 }), K(3, P { $0.armRY = -2; $0.lookY = -1 }), K(2, P { $0.armRY = -3; $0.lift = 1; $0.lookY = -1 }),
            K(10, P { $0.armRY = -2; $0.lookY = -1; $0.eyes = .tall }), K(3, P { $0.armRY = -1 })], airborne: true)
        c["push"] = ClipData(keys: [
            K(4, P { $0.armRY = 0; $0.lookX = 1 }), K(2, P { $0.armRY = -1; $0.lean = -1 }), K(1, P { $0.armRY = -2 }), K(2, P { $0.armRY = -2; $0.lean = 1 }, cut: true),
            K(10, P { $0.armRY = -1; $0.lookX = 1; $0.lookY = -1; $0.lean = 1 }), K(4, P { $0.lookX = 1 })])
        c["handoff"] = ClipData(keys: [
            K(4, rightHold.with { $0.armRY = 1; $0.lookX = 1 }), K(3, rightHold.with { $0.armRY = 1; $0.lean = 1; $0.lookX = 1 }),
            K(4, P { $0.lean = 1; $0.lookX = 1; $0.blush = true }, cut: true), K(6, P { $0.lookX = 1; $0.blush = true })])
        c["agent"] = ClipData(keys: [K(3, P { $0.armLY = -2; $0.armRY = -1 }), K(3, P { $0.armLY = -1; $0.armRY = -2 }), K(8, P { $0.lookX = 1 }), K(8, P { $0.lookX = -1 })])

        // Waiting on the user: clear, not frantic.
        c["ask"] = ClipData(keys: [
            K(10, P { $0.armRY = -3; $0.eyes = .tall }), K(2, P { $0.armRY = -2; $0.eyes = .tall }), K(2, P { $0.armRY = -3; $0.eyes = .tall }),
            K(2, P { $0.armRY = -2; $0.eyes = .tall }), K(10, P { $0.armRY = -3; $0.eyes = .tall; $0.lookY = 1 }), K(1, P { $0.armRY = -3; $0.eyes = .dash })])
        c["yourTurn"] = ClipData(keys: [K(8, P { $0.lookY = 1 }), K(3, P { $0.lookY = 1; $0.leg = [0, 0, 0, 1] }), K(3, P { $0.lookY = 1 }), K(3, P { $0.lookY = 1; $0.leg = [0, 0, 0, 1] }), K(8, P { $0.lookY = 1 }), K(1, blink)])
        c["watch"] = ClipData(keys: [K(8, P { $0.armLX = 1; $0.armLY = -1; $0.lookX = -1 }), K(3, P { $0.leg = [0, 0, 0, 1] }), K(3), K(3, P { $0.leg = [0, 0, 0, 1] }), K(4), K(1, blink)])
        c["flag"] = ClipData(keys: [K(4, P { $0.armRY = -2; $0.lookY = -1 }), K(4, P { $0.armRY = -3; $0.lookY = -1 })], held: true)

        // Events.
        c["done"] = ClipData(keys: [
            K(2, squash), K(2, armsUp1.with { $0.lift = 1 }), K(3, armsUp2.with { $0.lift = 2; $0.blush = true }),
            K(2, armsUp2.with { $0.lift = 1; $0.blush = true }), K(2, armsUp1.with { $0.squash = 1; $0.blush = true }), K(12, P { $0.blush = true }, cut: true)], airborne: true)
        c["hop"] = ClipData(keys: [K(2, squash), K(1, armsUp1), K(3, armsUp2.with { $0.lift = 1; $0.blush = true }), K(2, armsUp1.with { $0.squash = 1 }), K(5)], airborne: true)
        c["confetti"] = ClipData(keys: [K(2, squash), K(1, armsUp1), K(14, armsUp2.with { $0.blush = true }), K(4, armsUp1)])
        c["oops"] = ClipData(keys: [
            K(2, P { $0.dx = -1; $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }), K(2, P { $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }),
            K(2, P { $0.dx = 1; $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }), K(2, P { $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }),
            K(10, P { $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1; $0.squash = 1 })])
        c["bandage"] = ClipData(keys: [K(8, P { $0.eyes = .dash; $0.armRX = 1; $0.armRY = -2 }), K(3, P { $0.eyes = .dash; $0.armRX = 1; $0.armRY = -1 }), K(8, P { $0.eyes = .dash; $0.lean = -1; $0.lookY = 1 }), K(4, P { $0.eyes = .dash })])
        c["sweat"] = ClipData(keys: [K(6, P { $0.armRX = 1; $0.armRY = -2; $0.eyes = .dash }), K(3, P { $0.armRX = 1; $0.armRY = -1 }), K(8, P { $0.lookY = 1 })])
        c["conflict"] = ClipData(keys: [K(3, P { $0.squash = 1; $0.eyes = .cross }), K(10, P { $0.eyes = .cross; $0.armLY = 1; $0.armRY = 1 }), K(6, P { $0.eyes = .dash; $0.armLY = 1; $0.armRY = 1 })])
        c["conflictStare"] = ClipData(keys: [K(10, P { $0.profile = .right; $0.lookX = 1; $0.eyes = .dash }), K(2, P { $0.profile = .right; $0.lookX = 1 }), K(8, P { $0.profile = .right; $0.lookX = 1; $0.eyes = .dash; $0.lean = 1 })])
        c["hello"] = ClipData(keys: [
            K(1, P { $0.fade = 3; $0.squash = 1 }, cut: true), K(1, P { $0.fade = 2; $0.squash = 1 }), K(1, P { $0.fade = 1; $0.squash = 1 }),
            K(2, P { $0.squash = 1 }), K(2, armsUp1.with { $0.lift = 1 })] + waveRight(3) + [K(6)], airborne: true, maxDelta: 40)
        c["bye"] = ClipData(keys: waveRight(3) + [K(3), K(3, P { $0.fade = 1; $0.eyes = .dash }), K(3, P { $0.fade = 2; $0.eyes = .dash }), K(3, P { $0.fade = 3; $0.eyes = .dash }), K(2, P { $0.fade = 4 })], maxDelta: 40)
        c["wave"] = ClipData(keys: waveRight(3, base: P { $0.lookX = 1 }) + [K(4, P { $0.lookX = 1 })])
        c["highFive"] = ClipData(keys: [
            K(2, squash), K(1, P { $0.armRY = -1 }), K(3, P { $0.armRY = -2; $0.lean = 1; $0.lookX = 1 }), K(3, P { $0.armRY = -3; $0.lift = 1; $0.lean = 1; $0.eyes = .dash }),
            K(6, P { $0.armRY = -2; $0.lean = 1; $0.blush = true; $0.lookX = 1 }), K(1, P { $0.armRY = -1; $0.blush = true }), K(4, P { $0.blush = true })], airborne: true)
        c["parcel"] = ClipData(keys: [
            K(4, rightHold.with { $0.armRY = 1; $0.lookX = 1 }), K(4, rightHold.with { $0.armRY = 0; $0.lean = 1; $0.lookX = 1 }),
            K(4, P { $0.lean = 1; $0.lookX = 1 }, cut: true), K(6, P { $0.eyes = .dash })])
        c["bump"] = ClipData(keys: [K(2, P { $0.dx = -1; $0.squash = 1; $0.eyes = .dash }), K(3)])
        c["poke"] = ClipData(keys: [K(2, P { $0.squash = 1; $0.eyes = .dash }), K(2, P { $0.lift = 1 }), K(3)], airborne: true)
        c["spin"] = ClipData(keys: [K(2, P { $0.profile = .right }), K(2, P { $0.profile = .back }), K(2, P { $0.profile = .left }), K(3)])
        c["dizzy"] = ClipData(keys: [K(3, P { $0.eyes = .cross; $0.lean = -1 }), K(3, P { $0.eyes = .cross }), K(3, P { $0.eyes = .cross; $0.lean = 1 }), K(3, P { $0.eyes = .cross })])
        c["lean"] = ClipData(keys: [K(10, P { $0.lean = 1; $0.lookX = 1 }), K(1, P { $0.lean = 1; $0.eyes = .dash }), K(6, P { $0.lean = 1; $0.lookX = 1 })])
        c["peek"] = ClipData(keys: [K(8, P { $0.profile = .right; $0.lookX = 1 }), K(1, P { $0.profile = .right; $0.eyes = .dash }), K(6, P { $0.profile = .right; $0.lookX = 1 })])
        c["pet"] = ClipData(keys: [K(5, P { $0.lean = 1; $0.blush = true; $0.eyes = .dash }), K(2, P { $0.blush = true; $0.eyes = .dash }), K(5, P { $0.lean = -1; $0.blush = true; $0.eyes = .dash }), K(2, P { $0.blush = true; $0.eyes = .dash })])
        c["drag"] = ClipData(keys: [
            K(3, armsUp2.with { $0.eyes = .tall; $0.leg = [-1, 0, -1, 0] }), K(3, armsUp2.with { $0.eyes = .tall; $0.leg = [0, -1, 0, -1] })], airborne: true)
        c["listen"] = ClipData(keys: [K(6, armsUp1.with { $0.eyes = .tall; $0.lean = 1 }), K(6, armsUp1.with { $0.eyes = .tall })])
        c["listening"] = c["listen"]
        c["opening"] = ClipData(keys: [K(8, P { $0.eyes = .tall; $0.lean = 1 }), K(1, P { $0.lean = 1; $0.eyes = .dash }), K(4, P { $0.eyes = .tall; $0.lean = 1 })])
        c["reading"] = ClipData(keys: [K(6, P { $0.eyes = .tall; $0.lean = 1; $0.lookY = 1; $0.lookX = -1 }), K(6, P { $0.eyes = .tall; $0.lean = 1; $0.lookY = 1; $0.lookX = 1 })])
        c["chatTalk"] = ClipData(keys: [K(3, P { $0.armLY = -1 }), K(3, P { $0.armRY = -1; $0.lift = 1 }), K(3, P { $0.armLY = -1 }), K(3, P { $0.eyes = .dash })], airborne: true)
        c["talking"] = c["chatTalk"]
        for id in ["offline", "outOfCredits", "rateLimited", "unauthorized", "timeout"] { c[id] = ClipData(keys: slump(-1)) }
        c["tea"] = ClipData(keys: [
            K(10, rightHold.with { $0.armRY = 1 }), K(2, rightHold.with { $0.armRX = 2; $0.armRY = 0 }),
            K(6, rightHold.with { $0.armRX = 2; $0.armRY = -1; $0.eyes = .dash; $0.blush = true }), K(2, rightHold.with { $0.armRX = 2; $0.armRY = 0 }),
            K(8, rightHold.with { $0.armRY = 1; $0.blush = true })], held: true)
        c["coffee"] = c["tea"]
        return c
    }()
}
