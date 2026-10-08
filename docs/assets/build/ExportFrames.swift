// Offscreen exporter for README assets. Uses the app's own Renderer, Pen and PetModel; nothing is redrawn by hand.
//   export-frames cells                   -> JSON of every catalog clip as 12 fps cell frames (stdout)
//   export-frames scene <spec.json> <dir>  -> PNG frames of the real team panel (name tags, scarves, +N badge)
//   export-frames catalog                  -> AnimationCatalog.markdown(), same table as `Wigglet --dump-catalog`
// Built by export_frames.sh against app/Sources minus main.swift. Run with a throwaway HOME.
import AppKit
import SwiftUI

@main
struct ExportFrames {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count >= 4 && args[1] == "scene" { scene(spec: args[2], dir: args[3]); return }
        if args.count >= 2 && args[1] == "catalog" { print(AnimationCatalog.markdown()); return }
        if args.count >= 4 && args[1] == "card" { card(spec: args[2], out: args[3]); return }
        if args.count >= 4 && args[1] == "poses" { poses(spec: args[2], out: args[3]); return }
        cells()
    }

    static func cells() {
        let renderer = Renderer(m: PetModel())
        var out: [[String: Any]] = []
        for anim in AnimationCatalog.all {
            let steps = AnimationData.clips[anim.id]?.frameCount ?? max(1, Int((anim.duration * 12).rounded(.up)))
            var frames: [[[Int]]] = []
            for i in 0..<steps {
                let t = Double(i) / 12.0
                let pose = renderer.pose(anim.id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
                let pen = Pen(recordingU: 1)
                renderer.paintSprite(pen, pose, anim.id, t, t)
                renderer.paintEffects(pen, anim.id, pose, frame: renderer.clipFrame(anim.id, age: t), t: t, session: nil, now: Date(timeIntervalSinceReferenceDate: t))
                var cells: [[Int]] = []
                for (y, row) in pen.cells { for (x, c) in row { cells.append([x, y, Int(c)]) } }
                frames.append(cells.sorted { ($0[1], $0[0]) < ($1[1], $1[0]) })
            }
            out.append(["id": anim.id, "trigger": anim.trigger, "detected": anim.detected, "duration": anim.duration, "frames": frames])
        }
        let data = try! JSONSerialization.data(withJSONObject: ["fps": 12, "animations": out])
        FileHandle.standardOutput.write(data)
    }

    /// spec: {"scale": 4, "frames": 48, "sessions": [{"project": "docs", "mood": "working", "kind": "read", "say": "", "delta": ""}]}
    @MainActor static func scene(spec: String, dir: String) {
        let s = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: spec))) as! [String: Any]
        let fm = FileManager.default
        try? fm.removeItem(atPath: sessionsDir)
        try! fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        try! fm.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let nowMs = Date().timeIntervalSince1970 * 1000
        for (i, item) in (s["sessions"] as! [[String: Any]]).enumerated() {
            var obj: [String: Any] = ["sid": "s\(i)", "cwd": "", "project": "p", "startedAt": nowMs - 600_000 + Double(i) * 1000,
                                      "transcript": "", "lastTool": "", "toolCount": 3, "turnStart": NSNull(), "errorStreak": 0,
                                      "lastErrorAt": NSNull(), "mood": "working", "kind": "read", "say": "", "delta": "", "ts": nowMs]
            for (k, v) in item { obj[k] = v }
            try! JSONSerialization.data(withJSONObject: obj).write(to: URL(fileURLWithPath: sessionsDir + "/s\(i).json"))
        }
        let model = PetModel()
        model.scale = s["scale"] as? Double ?? 4
        model.loadSessions()
        // The app hides speech bubbles while the chat bar is open; "bubbles": false uses that state.
        if s["bubbles"] as? Bool == false { model.chatOpen = true }
        let panelW = CGFloat(teamPanelWidth(count: model.sessions.count, scale: model.scale))
        let margin: CGFloat = 40
        let start = Date()
        let frames = s["frames"] as? Int ?? 48
        for i in 0..<frames {
            let now = start.addingTimeInterval(Double(i) / 12)
            let view = Canvas { ctx, _ in
                ctx.translateBy(x: margin, y: 0)
                Renderer(m: model).drawTeam(&ctx, size: CGSize(width: panelW, height: canvasH), now: now)
            }
            .frame(width: panelW + margin * 2, height: canvasH + margin)
            let r = ImageRenderer(content: view)
            r.scale = s["px"] as? Double ?? 2
            guard let cg = r.cgImage else { fatalError("render failed") }
            let rep = NSBitmapImageRep(cgImage: cg)
            try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: String(format: "%@/%03d.png", dir, i)))
        }
        print("\(frames) frames, \(model.sessions.count) sessions -> \(dir)")
    }
}

extension ExportFrames {
    /// Looping cell frames for README scenes, from the app's own pose data, props, effects and scarves.
    /// Lift and dx are applied, so hops and shakes show. spec: {"frames": 48, "items": [{"id": "ask", "accent": "#5AA9FF"}]}
    static func poses(spec: String, out: String) {
        let s = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: spec))) as! [String: Any]
        let n = s["frames"] as? Int ?? 48
        let renderer = Renderer(m: PetModel())
        var items: [[String: Any]] = []
        for item in s["items"] as! [[String: Any]] {
            let id = item["id"] as! String
            var accent: Color?
            if let hex = item["accent"] as? String, let v = UInt32(hex.dropFirst(), radix: 16) {
                accent = Color(.sRGB, red: Double((v >> 16) & 255) / 255, green: Double((v >> 8) & 255) / 255, blue: Double(v & 255) / 255, opacity: 1)
            }
            var frames: [[[Int]]] = []
            for i in 0..<n {
                let t = Double(i) / 12
                let pose = renderer.pose(id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
                let pen = Pen(recordingU: 1)
                renderer.paintSprite(pen, pose, id, t, t, accent: accent)
                renderer.paintEffects(pen, id, pose, frame: renderer.clipFrame(id, age: t), t: t, session: nil, now: Date(timeIntervalSinceReferenceDate: t))
                var cells: [[Int]] = []
                for (y, row) in pen.cells { for (x, c) in row { cells.append([x + pose.dx, y - pose.lift, Int(c)]) } }
                frames.append(cells)
            }
            items.append(["id": id, "frames": frames])
        }
        try! JSONSerialization.data(withJSONObject: ["items": items]).write(to: URL(fileURLWithPath: out))
    }

    /// The real hover card (`ActivityView`) for one demo session, rendered offscreen on a solid backdrop.
    /// spec: {"session": {...}, "events": [["edit","routes.ts +12 −3"], ...], "prompt": "...", "message": "..."}
    @MainActor static func card(spec: String, out: String) {
        let s = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: spec))) as! [String: Any]
        let fm = FileManager.default
        try? fm.removeItem(atPath: sessionsDir)
        try! fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
        var obj = s["session"] as! [String: Any]
        let now = Date().timeIntervalSince1970 * 1000
        obj["ts"] = now; obj["turnStart"] = now - 252_000; obj["startedAt"] = now - 900_000
        try! JSONSerialization.data(withJSONObject: obj).write(to: URL(fileURLWithPath: sessionsDir + "/card.json"))
        let model = PetModel()
        model.loadSessions()
        let events = (s["events"] as? [[String]]) ?? []
        model.sessions[0].events = events.enumerated().map { i, e in
            Ev(ts: now - Double(events.count - i) * 41_000, kind: Kind(rawValue: e[0]) ?? .think, text: e[1])
        }
        model.cardSid = model.sessions[0].sid
        let watcher = TranscriptWatcher()
        watcher.preview(.init(message: s["message"] as? String ?? "", prompt: s["prompt"] as? String ?? ""))
        let dark = (s["dark"] as? Bool) ?? true
        ActivityView.offscreen = true
        let view = ActivityView(model: model, watcher: watcher)
            .environment(\.colorScheme, dark ? .dark : .light)
            .background(dark ? Color(red: 0.08, green: 0.067, blue: 0.06) : Color(red: 0.965, green: 0.945, blue: 0.906))
        let r = ImageRenderer(content: view)
        r.scale = 2
        guard let cg = r.cgImage else { fatalError("card render failed") }
        try! NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: out))
        print("card -> \(out)")
    }
}

// Stand-ins for symbols that live in app/Sources/main.swift, which is not compiled here.
final class AppDelegate {
    static var shared = AppDelegate()
    let model = PetModel()
    let chat = ChatModel()
    var soundsOn = false
    func jump(_ s: SessionPet) {}
    func applyScale(_ v: Double) {}
    func rebuildMenu() {}
    func resetPosition() {}
    func toggleLogin() {}
}
let canvasH: CGFloat = 280
