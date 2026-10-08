// Offscreen exporter for README assets. Uses the app's own Renderer, Pen and PetModel; nothing is redrawn by hand.
//   export-frames cells                   -> JSON of every catalog clip as 12 fps cell frames (stdout)
//   export-frames scene <spec.json> <dir>  -> PNG frames of the real team panel (name tags, scarves, +N badge)
//   export-frames catalog                  -> AnimationCatalog.markdown(), same table as `ClawdPet --dump-catalog`
// Built by export_frames.sh against app/Sources minus main.swift. Run with a throwaway HOME.
import AppKit
import SwiftUI

@main
struct ExportFrames {
    @MainActor static func main() {
        let args = CommandLine.arguments
        if args.count >= 4 && args[1] == "scene" { scene(spec: args[2], dir: args[3]); return }
        if args.count >= 2 && args[1] == "catalog" { print(AnimationCatalog.markdown()); return }
        cells()
    }

    static func cells() {
        let renderer = Renderer(m: PetModel())
        var out: [[String: Any]] = []
        for anim in AnimationCatalog.all {
            let steps = max(1, Int((anim.duration * 12).rounded(.up)))
            var frames: [[[Int]]] = []
            for i in 0..<steps {
                let t = Double(i) / 12.0
                let pose = renderer.pose(anim.id, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
                let pen = Pen(recordingU: 1)
                renderer.paintSprite(pen, pose, anim.id, t, t)
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

// Stand-ins for symbols that live in app/Sources/main.swift, which is not compiled here.
final class AppDelegate {
    static var shared = AppDelegate()
    let model = PetModel()
}
let canvasH: CGFloat = 280
