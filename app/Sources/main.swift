import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

if CommandLine.arguments.contains("--dump-catalog") {
    print(AnimationCatalog.markdown())
    exit(0)
}
if CommandLine.arguments.contains("--frame-audit") {
    exit(runFrameAudit())
}
if CommandLine.arguments.contains("--pixel-audit") {
    exit(runPixelAudit())
}
if CommandLine.arguments.contains("--hook") { runHookMode() }
if CommandLine.arguments.contains("--gen-update-key") || CommandLine.arguments.contains("--sign-update") { runUpdateKeyTool(CommandLine.arguments) }
// Prints where the calling shell's session would be recorded as running (same walk the hook does).
if CommandLine.arguments.contains("--host-probe") {
    let h = findHost()
    print("bundle=\(h.bundleId) pid=\(h.pid) tty=\(h.tty) app=\((h.appPath as NSString).lastPathComponent)")
    exit(0)
}
// `--jump <sid>`: runs "Jump to session" for one session file and prints the outcome (testing).
if let i = CommandLine.arguments.firstIndex(of: "--jump"), i + 1 < CommandLine.arguments.count {
    let model = PetModel()
    model.loadSessions()
    guard let s = model.sessions.first(where: { $0.sid == CommandLine.arguments[i + 1] }) else { print("no such session"); exit(1) }
    let r = Jump.go(s)
    print(r.ok ? "PASS exact" : "PARTIAL \(r.note)")
    exit(0)
}
if CommandLine.arguments.contains("--install-hooks") { do { try HookInstaller.install(); print("hooks installed in \(settingsPath)") } catch { print(error.localizedDescription); exit(1) }; exit(0) }
if CommandLine.arguments.contains("--remove-hooks") { do { try HookInstaller.remove(); print("hooks removed") } catch { print(error.localizedDescription); exit(1) }; exit(0) }
let teamDemoFlag = CommandLine.arguments.contains("--team-demo")
let chatDemoStatus: ChatStatus? = {
    let args = CommandLine.arguments
    guard let i = args.firstIndex(of: "--chat-demo"), i + 1 < args.count else { return nil }
    return ChatStatus(rawValue: args[i + 1])
}()
if CommandLine.arguments.contains("--demo-team") {
    let args = CommandLine.arguments
    var n = 1
    if let i = args.firstIndex(of: "--demo-team"), i + 1 < args.count, let v = Int(args[i + 1]) { n = v }
    n = min(6, max(1, n))
    try? FileManager.default.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
    let base = 1_700_000_000_000.0
    let letters = Array("abcdef")
    let ts = Date().timeIntervalSince1970 * 1000
    for i in 0..<n {
        let sid = "demo-\(i + 1)"
        let obj: [String: Any] = [
            "sid": sid, "cwd": "", "project": "demo-\(letters[i])", "startedAt": base + Double(i) * 1000,
            "transcript": "", "lastTool": "", "toolCount": 1, "turnStart": NSNull(), "errorStreak": 0,
            "lastErrorAt": NSNull(), "mood": "working", "kind": "read", "say": "", "delta": "", "ts": ts
        ]
        let path = sessionsDir + "/" + sid + ".json"
        if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: URL(fileURLWithPath: path)) }
        print(path)
    }
    if !teamDemoFlag { exit(0) }
}
if CommandLine.arguments.contains("--discover") {
    for d in TranscriptDiscovery().scan(maxAgeMs: HideAfter.ms) {
        print(d.sid.prefix(8), d.entrypoint, Int((Date().timeIntervalSince1970 * 1000 - d.modified) / 60_000), "min", d.title.isEmpty ? d.cwd : d.title)
    }
    exit(0)
}
if CommandLine.arguments.contains("--selftest") {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
    if !home.contains("/tmp/") && !home.contains("session-pet-test") { exit(2) }
    if let problem = ChatAPI.runChecks() {
        print(problem)
        exit(1)
    }
    if let problem = AnimationCatalog.runChecks() {
        print(problem)
        exit(1)
    }
    if let problem = Updater.selfCheck() {
        print(problem)
        exit(1)
    }
    if let problem = TranscriptDiscovery.selfCheck() {
        print(problem)
        exit(1)
    }
    if let problem = TranscriptReader.selfCheck() {
        print(problem)
        exit(1)
    }
    // Claude desktop jump link: the format Claude Code's /desktop handoff uses.
    var probe = SessionPet(sid: "abc-123", cwd: "/tmp/my proj", project: "p", startedAt: 0, transcript: "", lastTool: "", toolCount: 0, turnStart: nil, errorStreak: 0, lastErrorAt: nil, mood: "working", kind: .none, say: "", delta: "", ts: 0)
    probe.hostBundleId = Jump.claudeDesktop
    if Jump.desktopLink(probe)?.absoluteString != "claude://resume?session=abc-123&cwd=/tmp/my%20proj" { print("desktop link \(Jump.desktopLink(probe)?.absoluteString ?? "")"); exit(1) }
    // Connect / disconnect round trip against this throwaway HOME, including an old ClawdPet hook to replace.
    do {
        let dir = (settingsPath as NSString).deletingLastPathComponent
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let old: [String: Any] = ["hooks": ["Stop": [["hooks": [["type": "command", "command": "/Applications/ClawdPet.app/Contents/MacOS/ClawdPet --hook"]]]]], "keep": true]
        try JSONSerialization.data(withJSONObject: old).write(to: URL(fileURLWithPath: settingsPath))
        try HookInstaller.install()
        guard HookInstaller.isInstalled, let s = HookInstaller.load(), let hooks = s["hooks"] as? [String: Any],
              let stop = hooks["Stop"] as? [[String: Any]], stop.count == 1, s["keep"] as? Bool == true else { print("connect"); exit(1) }
        try HookInstaller.remove()
        if HookInstaller.isInstalled || (HookInstaller.load()?["keep"] as? Bool) != true { print("disconnect"); exit(1) }
    } catch { print("hooks \(error)"); exit(1) }
    let fm = FileManager.default
    try? fm.createDirectory(atPath: sessionsDir, withIntermediateDirectories: true)
    if let files = try? fm.contentsOfDirectory(atPath: sessionsDir) {
        for f in files where f.hasPrefix("selftest-") { try? fm.removeItem(atPath: sessionsDir + "/" + f) }
    }
    func write(_ name: String, _ startedAt: Double) {
        let obj: [String: Any] = ["sid": name, "startedAt": startedAt, "ts": Date().timeIntervalSince1970 * 1000]
        let path = sessionsDir + "/" + name + ".json"
        if let d = try? JSONSerialization.data(withJSONObject: obj) { try? d.write(to: URL(fileURLWithPath: path)) }
    }
    let model = PetModel()
    func cleanup() {
        try? fm.removeItem(atPath: sessionsDir + "/selftest-a.json")
        try? fm.removeItem(atPath: sessionsDir + "/selftest-b.json")
    }
    func check(_ want: [String]) {
        model.loadSessions()
        let got = model.sessions.map { $0.sid }
        if got != want {
            cleanup()
            print(got.joined(separator: " "))
            exit(1)
        }
    }
    write("selftest-a", 1000)
    check(["selftest-a"])
    write("selftest-b", 2000)
    check(["selftest-a", "selftest-b"])
    try? fm.removeItem(atPath: sessionsDir + "/selftest-a.json")
    check(["selftest-b"])
    cleanup()
    print("selftest ok")
    exit(0)
}

let canvasH: CGFloat = 280

final class ChatPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// The hover card panel: becomes key when clicked, so Tab, Return and Esc work without activating the app on hover.
final class CardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

final class DragView: NSView {
    let model: PetModel
    let clock: FrameClock
    weak var delegate: AppDelegate?
    var startMouse = NSPoint.zero, startOrigin = NSPoint.zero, moved = false
    var samples: [(NSPoint, TimeInterval)] = []

    init(model: PetModel, clock: FrameClock, delegate: AppDelegate) {
        self.model = model; self.clock = clock; self.delegate = delegate
        super.init(frame: NSRect(x: 0, y: 0, width: teamPanelWidth(count: model.displaySessions.count, scale: model.scale), height: canvasH))
        let host = NSHostingView(rootView: PetView(model: model, clock: clock))
        host.frame = bounds; host.autoresizingMask = [.width, .height]
        addSubview(host)
        // macOS treats SwiftUI-drawn pixels as click-through. A nearly invisible (but not fully transparent)
        // layer under the sprite makes the window server deliver mouse events to us.
        pad.wantsLayer = true
        pad.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.01).cgColor
        addSubview(pad, positioned: .below, relativeTo: host)
    }
    let pad = NSView()
    var areas: [NSTrackingArea] = []
    var lastMove = Date()
    var slotFrames: [NSRect] {
        let u = CGFloat(model.scale)
        let n = min(6, max(1, model.displaySessions.count))
        let stride = 13 * u + 8
        let h = 10 * u + 12
        return (0..<n).map { i in NSRect(x: 8 + CGFloat(i) * stride, y: 8, width: 13 * u, height: h) }
    }
    var badgeFrame: NSRect? {
        guard model.displaySessions.count > 6 else { return nil }
        let u = CGFloat(model.scale)
        let stride = 13 * u + 8
        return NSRect(x: 8 + 6 * stride, y: 8, width: 44, height: 10 * u + 12)
    }
    override func layout() {
        super.layout()
        let frames = slotFrames + (badgeFrame.map { [$0] } ?? [])
        pad.frame = frames.dropFirst().reduce(frames[0]) { $0.union($1) }
    }
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for a in areas { removeTrackingArea(a) }
        areas = []
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .mouseMoved, .activeAlways]
        for (i, r) in slotFrames.enumerated() {
            let a = NSTrackingArea(rect: r, options: opts, owner: self, userInfo: ["slot": i])
            addTrackingArea(a); areas.append(a)
        }
        if let r = badgeFrame {
            let a = NSTrackingArea(rect: r, options: opts, owner: self, userInfo: ["badge": true])
            addTrackingArea(a); areas.append(a)
        }
    }
    override func mouseEntered(with e: NSEvent) {
        let info = e.trackingArea?.userInfo
        if (info?["badge"] as? Bool) == true {
            model.badgeHover = true
            model.hoveredSid = nil
            model.hover = true
            toolTip = Array(model.displaySessions.dropFirst(6)).map(\.cwd).joined(separator: "\n")
            model.objectWillChange.send()
            delegate?.hoverChanged(true)
            return
        }
        guard let i = info?["slot"] as? Int else { return }
        let list = model.displaySessions
        model.badgeHover = false
        guard i < list.count else { return }
        let s = list[i]
        model.hoveredSid = s.sid
        model.cardSid = s.sid
        model.hoverBegan = Date()
        model.hover = true
        toolTip = s.cwd.isEmpty ? model.sessionTag(s) : s.cwd
        model.objectWillChange.send()
        delegate?.hoverChanged(true)
    }
    override func mouseExited(with e: NSEvent) {
        model.hover = false
        model.hoveredSid = nil
        model.hoverBegan = nil
        model.leanSid = nil
        model.badgeHover = false
        toolTip = nil
        model.objectWillChange.send()
        delegate?.hoverChanged(false)
    }
    override func mouseMoved(with e: NSEvent) {
        let now = Date(), dt = now.timeIntervalSince(lastMove); lastMove = now
        model.petAcc = model.petAcc * exp(-dt * 1.2) + abs(Double(e.deltaX))
        if model.petAcc > 500 && !model.isDragging {
            let sid = model.hoveredSid ?? model.grabbedSid
            model.petSid = sid
            model.petUntil = now.addingTimeInterval(2.5)
            if let sid { model.dizzyUntil[sid] = now.addingTimeInterval(1.2) }
            model.petAcc = 0
        }
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ p: NSPoint) -> NSView? {
        let l = superview != nil ? convert(p, from: superview) : p
        if slotFrames.contains(where: { $0.contains(l) }) { return self }
        if let b = badgeFrame, b.contains(l) { return self }
        return nil
    }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    func sid(at loc: NSPoint) -> String? {
        guard let i = slotFrames.firstIndex(where: { $0.contains(loc) }) else { return nil }
        let list = model.displaySessions
        guard i < list.count else { return nil }
        return list[i].sid
    }
    func refreshBump() {
        let list = Array(model.displaySessions.prefix(6))
        var frames: [String: AnimationCatalog.SlotBox] = [:]
        for (i, s) in list.enumerated() where i < slotFrames.count {
            let r = slotFrames[i]
            frames[s.sid] = AnimationCatalog.SlotBox(x: r.origin.x, y: r.origin.y, w: r.width, h: r.height)
        }
        if let g = model.grabbedSid {
            model.bumpSids = AnimationCatalog.bumpSids(grabbed: g, frames: frames)
        } else {
            model.bumpSids = []
        }
    }
    func originNearEdge(_ origin: NSPoint) -> Bool {
        NSScreen.screens.contains { s in
            let f = s.frame
            return abs(origin.x - f.minX) <= 8 || abs(origin.x - f.maxX) <= 8 || abs(origin.y - f.minY) <= 8 || abs(origin.y - f.maxY) <= 8
        }
    }
    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation; startOrigin = window?.frame.origin ?? .zero; moved = false
        samples = [(startMouse, ProcessInfo.processInfo.systemUptime)]
        delegate?.glider.stop()
    }
    override func mouseDragged(with e: NSEvent) {
        let cur = NSEvent.mouseLocation
        if !moved && hypot(cur.x - startMouse.x, cur.y - startMouse.y) > 3 {
            moved = true
            model.grabbedSid = sid(at: convert(e.locationInWindow, from: nil)) ?? model.hoveredSid
            model.isDragging = true
            clock.retune()
            delegate?.hoverChanged(false)
        }
        guard moved, let w = window else { return }
        w.setFrameOrigin(NSPoint(x: startOrigin.x + cur.x - startMouse.x, y: startOrigin.y + cur.y - startMouse.y))
        model.peeking = originNearEdge(w.frame.origin)
        refreshBump()
        let now = ProcessInfo.processInfo.systemUptime
        if let last = samples.last { model.vx = model.vx * 0.6 + Double(cur.x - last.0.x) * 0.4 }
        samples.append((cur, now)); samples = samples.filter { now - $0.1 < 0.12 }
        delegate?.positionChat()
    }
    override func mouseUp(with e: NSEvent) {
        if moved {
            model.glideSid = model.grabbedSid
            model.grabbedSid = nil
            model.peeking = false
            model.bumpSids = []
            model.isDragging = false; model.dropAt = Date()
            if let a = samples.first, let b = samples.last, b.1 - a.1 > 0.02 {
                let dt = b.1 - a.1
                delegate?.glider.fling(vx: Double(b.0.x - a.0.x) / dt, vy: Double(b.0.y - a.0.y) / dt)
            } else { delegate?.savePosition() }
            clock.retune()
        } else {
            let loc = convert(e.locationInWindow, from: nil)
            if let i = slotFrames.firstIndex(where: { $0.contains(loc) }) {
                let list = model.displaySessions
                if i < list.count {
                    let s = list[i]
                    model.selectedSid = s.sid
                    model.sessionContext = model.contextLine(s)
                    model.clickSid = s.sid
                    let now = Date()
                    if let prev = model.lastClick[s.sid], now.timeIntervalSince(prev) < 0.35 {
                        model.spinUntil[s.sid] = now.addingTimeInterval(0.8)
                        model.pokeUntil[s.sid] = .distantPast
                    } else {
                        model.pokeUntil[s.sid] = now.addingTimeInterval(0.6)
                    }
                    model.lastClick[s.sid] = now
                }
                model.click(); delegate?.toggleChat()
            }
        }
    }
    override func rightMouseDown(with e: NSEvent) { NSMenu.popUpContextMenu(delegate?.buildMenu() ?? NSMenu(), with: e, for: self) }
}

/// Throw physics: the pet slides after a flick, bounces off the screen edges and settles.
final class Glider {
    weak var delegate: AppDelegate?
    var timer: Timer?
    var vx = 0.0, vy = 0.0
    init(_ d: AppDelegate) { delegate = d }
    func stop() { timer?.invalidate(); timer = nil; delegate?.model.isGliding = false; delegate?.clock.retune() }
    func fling(vx: Double, vy: Double) {
        let sp = hypot(vx, vy)
        guard sp > 350, let d = delegate else { d(); return }
        self.vx = min(2800, max(-2800, vx)); self.vy = min(2800, max(-2800, vy))
        d.model.isGliding = true
        d.clock.retune()
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 1 / 60, repeats: true) { [weak self] _ in self?.step() }
    }
    private func d() { delegate?.savePosition() }
    private func step() {
        guard let d = delegate, let w = d.panel else { return stop() }
        let dt = 1.0 / 60
        var o = w.frame.origin
        o.x += CGFloat(vx * dt); o.y += CGFloat(vy * dt)
        let f = d.bounds(for: w.frame)
        if o.x < f.minX { o.x = f.minX; vx = abs(vx) * 0.6; d.model.dropAt = Date() }
        if o.x > f.maxX { o.x = f.maxX; vx = -abs(vx) * 0.6; d.model.dropAt = Date() }
        if o.y < f.minY { o.y = f.minY; vy = abs(vy) * 0.6; d.model.dropAt = Date() }
        if o.y > f.maxY { o.y = f.maxY; vy = -abs(vy) * 0.6; d.model.dropAt = Date() }
        w.setFrameOrigin(o)
        d.model.vx = vx * 0.02
        let k = pow(0.04, dt)    // friction
        vx *= k; vy *= k
        d.positionChat()
        if hypot(vx, vy) < 30 { stop(); d.savePosition() }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    static var shared: AppDelegate!
    let model = PetModel()
    let clock = FrameClock()
    let chat = ChatModel()
    let updater = Updater.shared
    var panel: NSPanel!
    var chatPanel: ChatPanel!
    var chatHost: NSHostingView<ChatView>!
    var item: NSStatusItem!
    var glider: Glider!
    var hotKey: EventHotKeyRef?
    var activityPanel: CardPanel!
    var activityHost: NSHostingView<ActivityView>!
    let watcher = TranscriptWatcher()
    var toastPanel: NSPanel!
    var toastHost: NSHostingView<ToastView>!
    var cardGraceUntil = Date.distantPast
    var hoverWork: DispatchWorkItem?
    let appState = AppState()
    var mainWindow: NSWindow!
    /// Test runs use a throwaway HOME; they never open windows or ask anything.
    let testHome: Bool = {
        let real = String(cString: getpwuid(getuid()).pointee.pw_dir)
        return (ProcessInfo.processInfo.environment["HOME"] ?? real) != real
    }()
    var soundsOn: Bool { get { UserDefaults.standard.bool(forKey: "sounds") } set { UserDefaults.standard.set(newValue, forKey: "sounds") } }

    func applicationDidFinishLaunching(_ n: Notification) {
        AppDelegate.shared = self
        let me = Bundle.main.bundleIdentifier ?? ""
        if NSRunningApplication.runningApplications(withBundleIdentifier: me).count > 1 { NSApp.terminate(nil) }
        glider = Glider(self)
        if CommandLine.arguments.contains("--demo") {
            model.demo = ["idle", "hello", "think", "read", "edit", "bash", "search", "web", "agent", "plan", "compact", "ask", "yourTurn", "done", "oops", "listen", "chatThink", "chatTalk", "drag", "glide", "sleep", "bye", "test", "build", "git", "install", "pet"]
        }
        if CommandLine.arguments.contains("--gallery") {
            model.demo = AnimationCatalog.all.map { $0.id }
            let args = CommandLine.arguments
            if let i = args.firstIndex(of: "--zoom"), i + 1 < args.count, let z = Double(args[i + 1]) {
                model.scale = max(1, (model.scale * z).rounded())
            }
        }
        if teamDemoFlag {
            model.teamDemo = true
            model.loadSessions()
        }

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: teamPanelWidth(count: model.displaySessions.count, scale: model.scale), height: canvasH),
                        styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false; panel.backgroundColor = .clear; panel.hasShadow = false
        panel.level = .floating; panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        clock.panel = panel
        panel.contentView = DragView(model: model, clock: clock, delegate: self)
        if let s = UserDefaults.standard.string(forKey: "pos") {
            panel.setFrameOrigin(NSPointFromString(s))
            if !NSScreen.screens.contains(where: { $0.frame.intersects(panel.frame) }) { resetPosition() }
        } else { resetPosition() }
        panel.orderFrontRegardless()
        clock.start(model)

        // hover activity card
        activityPanel = CardPanel(contentRect: NSRect(x: 0, y: 0, width: 340, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        activityPanel.isOpaque = false; activityPanel.backgroundColor = .clear; activityPanel.hasShadow = false
        activityPanel.level = .floating; activityPanel.ignoresMouseEvents = false; activityPanel.hidesOnDeactivate = false
        activityPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        activityHost = NSHostingView(rootView: ActivityView(model: model, watcher: watcher,
                                                            onJump: { [weak self] s in self?.jump(s) },
                                                            onClose: { [weak self] in self?.hideCard() }))
        activityPanel.contentView = activityHost
        toastPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 300, height: 40), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        toastPanel.isOpaque = false; toastPanel.backgroundColor = .clear; toastPanel.hasShadow = false
        toastPanel.level = .floating; toastPanel.ignoresMouseEvents = true
        toastPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        toastHost = NSHostingView(rootView: ToastView(model: model))
        toastPanel.contentView = toastHost

        // chat bar
        chatPanel = ChatPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 80), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        chatPanel.isOpaque = false; chatPanel.backgroundColor = .clear; chatPanel.hasShadow = false
        chatPanel.level = .floating; chatPanel.hidesOnDeactivate = false
        chatPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        chatHost = NSHostingView(rootView: ChatView(chat: chat))
        chatPanel.contentView = chatHost
        chat.onChange = { [weak self] in DispatchQueue.main.async { self?.positionChat() }; self?.model.chatBusy = self?.chat.isBusy ?? false }
        chat.onReply = { [weak self] in self?.model.chatReplyAt = Date() }
        chat.onClose = { [weak self] in self?.closeChat() }
        chat.onListening = { [weak self] on in self?.model.listening = on }
        chat.onStatus = { [weak self] status in
            self?.model.chatStatus = status
            self?.model.objectWillChange.send()
        }

        model.cursor = { [weak self] in
            guard let self, let w = self.panel else { return .zero }
            let m = NSEvent.mouseLocation, f = w.frame
            let cx = f.midX, cy = f.minY + 14 + CGFloat(self.model.scale) * 4
            return CGPoint(x: max(-1, min(1, (m.x - cx) / 500)), y: max(-1, min(1, -(m.y - cy) / 400)))
        }
        model.onSound = { [weak self] k in
            guard let self, self.soundsOn else { return }
            NSSound(named: k == "waiting" ? "Ping" : "Glass")?.play()
        }

        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "✺"
        item.menu = buildMenu()
        registerHotKey()
        if let chatDemoStatus {
            chat.status = chatDemoStatus
            model.chatStatus = chatDemoStatus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openChat() }
        } else if CommandLine.arguments.contains("--chat") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { self.openChat() }
        }
        Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            self.model.poll()
            for k in self.model.soundNow { self.model.onSound(k) }
            let waiting = self.model.sessions.filter { $0.mood == "waiting" }.count
            self.item.button?.title = waiting > 0 ? "\(waiting)" : "✺"
            self.fitPanel()
            self.positionActivity()
            // Close the card once the pointer has left both the Wigglet and the card (after a short grace).
            if self.activityPanel.isVisible && !self.model.hover && !self.model.cardHover && Date() > self.cardGraceUntil
                && !self.activityPanel.isKeyWindow {
                self.hideCard()
            }
        }

        // Main window: setup, sessions, animations, settings. Opens on its own until Wigglet is connected.
        appState.delegate = self
        mainWindow = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1040, height: 700),
                              styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered, defer: false)
        mainWindow.title = PRODUCT_NAME
        mainWindow.titleVisibility = .hidden
        mainWindow.titlebarAppearsTransparent = true
        mainWindow.appearance = NSAppearance(named: .darkAqua)
        mainWindow.backgroundColor = NSColor(srgbRed: 0x14 / 255.0, green: 0x14 / 255.0, blue: 0x13 / 255.0, alpha: 1)
        mainWindow.isReleasedWhenClosed = false
        mainWindow.contentView = NSHostingView(rootView: MainView(model: model, state: appState))
        mainWindow.center()
        mainWindow.setFrameAutosaveName("WiggletMain")
        NSApp.mainMenu = buildMainMenu()
        if CommandLine.arguments.contains("--show-window") {
            let args = CommandLine.arguments
            let pane = args.firstIndex(of: "--pane").flatMap { $0 + 1 < args.count ? AppState.Pane(rawValue: args[$0 + 1]) : nil }
            showMain(pane ?? .home)
        }
        if !testHome && (!HookInstaller.isInstalled || !UserDefaults.standard.bool(forKey: "setupSeen")) {
            UserDefaults.standard.set(true, forKey: "setupSeen")
            showMain(.home)
        }
        Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in self?.appState.refresh() }
        // Update checks only run for a real install, never under a test HOME unless a test feed is set.
        if !testHome || ProcessInfo.processInfo.environment["WIGGLET_UPDATE_FEED"] != nil {
            updater.onChange = { [weak self] in self?.rebuildMenu() }
            updater.start()
        }
    }

    // MARK: positioning
    func bounds(for frame: NSRect) -> NSRect {
        let u = CGFloat(model.scale)
        let sc = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = sc.visibleFrame
        let w = panel?.frame.width ?? CGFloat(teamPanelWidth(count: model.displaySessions.count, scale: model.scale))
        return NSRect(x: vf.minX - w / 2 + 6 * u, y: vf.minY - 14,
                      width: vf.width - 12 * u, height: vf.height - 8 * u)
    }
    func fitPanel() {
        let w = CGFloat(teamPanelWidth(count: model.displaySessions.count, scale: model.scale))
        if abs(panel.frame.width - w) > 0.5 {
            var f = panel.frame
            f.size.width = w
            panel.setFrame(f, display: true)
            panel.contentView?.needsLayout = true
            panel.contentView?.updateTrackingAreas()
        }
    }
    func resetPosition() {
        let f = (NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        panel.setFrameOrigin(NSPoint(x: f.maxX - panel.frame.width + 20, y: f.minY - 6))
        UserDefaults.standard.removeObject(forKey: "pos"); positionChat()
    }
    func savePosition() {
        let scale = panel.backingScaleFactor
        var origin = panel.frame.origin
        origin.x = (origin.x * scale).rounded() / scale
        origin.y = (origin.y * scale).rounded() / scale
        panel.setFrameOrigin(origin)
        UserDefaults.standard.set(NSStringFromPoint(origin), forKey: "pos")
    }

    func positionChat() {
        guard chatPanel != nil, chatPanel.isVisible else { return }
        chatHost.layoutSubtreeIfNeeded()
        let size = chatHost.fittingSize
        chatPanel.setContentSize(size)
        let u = CGFloat(model.scale), f = panel.frame
        let sc = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = sc.visibleFrame
        let feet = f.minY + 14, head = feet + 8 * u
        let below = head + size.height + 16 > vf.maxY
        if chat.placeBelow != below { chat.placeBelow = below }
        var x = f.midX - size.width / 2
        x = max(vf.minX + 4, min(vf.maxX - size.width - 4, x))
        let y = below ? feet - size.height - 6 : head + 8
        chatPanel.setFrameOrigin(NSPoint(x: x, y: max(vf.minY + 4, y)))
    }
    func hoverChanged(_ on: Bool) {
        hoverWork?.cancel()
        if on {
            let w = DispatchWorkItem { [weak self] in self?.showActivity() }
            hoverWork = w; DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: w)
        } else {
            // Leave time to travel from the Wigglet onto the card.
            cardGraceUntil = Date().addingTimeInterval(0.45)
            if model.isDragging { hideCard() }
        }
    }
    func showActivity() {
        guard !model.chatOpen, !model.isDragging, !model.isGliding, model.hover else { return }
        if let s = model.sessions.first(where: { $0.sid == model.cardSid }), model.showLatest { watcher.watch(s.transcript) } else { watcher.stop() }
        positionActivity(); activityPanel.orderFrontRegardless()
    }
    func hideCard() {
        activityPanel.orderOut(nil)
        watcher.stop()
        model.cardHover = false
    }
    func jump(_ s: SessionPet) {
        if Jump.needsAutomation(s) && !UserDefaults.standard.bool(forKey: "explainedAutomation") {
            UserDefaults.standard.set(true, forKey: "explainedAutomation")
            let a = NSAlert()
            a.messageText = "Let \(PRODUCT_NAME) pick the right tab?"
            a.informativeText = "To jump to the exact \(Jump.hostName(s)) tab, macOS will ask once whether \(PRODUCT_NAME) may control \(Jump.hostName(s)). It only selects the tab whose terminal matches this session. If you say no, it still brings the app forward."
            a.addButton(withTitle: "Continue")
            NSApp.activate(ignoringOtherApps: true)
            a.runModal()
        }
        let r = Jump.go(s)
        hideCard()
        if !r.note.isEmpty { showToast(r.note) }
    }
    func showToast(_ text: String) {
        model.toast = text
        model.objectWillChange.send()
        toastHost.layoutSubtreeIfNeeded()
        let size = toastHost.fittingSize
        toastPanel.setContentSize(size)
        let f = panel.frame, u = CGFloat(model.scale)
        toastPanel.setFrameOrigin(NSPoint(x: f.midX - size.width / 2, y: f.minY + 14 + 9 * u))
        toastPanel.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.6) { [weak self] in
            if self?.model.toast == text { self?.toastPanel.orderOut(nil) }
        }
    }
    func positionActivity() {
        guard activityPanel != nil, activityPanel.isVisible else { return }
        activityHost.layoutSubtreeIfNeeded()
        let size = activityHost.fittingSize
        activityPanel.setContentSize(size)
        let u = CGFloat(model.scale), f = panel.frame
        let sc = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = sc.visibleFrame
        // Beside the team, never over a Wigglet: left of the first slot, else right of the last.
        let team = CGFloat(teamPanelWidth(count: model.displaySessions.count, scale: model.scale))
        var x = f.minX + 8 - size.width
        if x < vf.minX + 4 { x = f.minX + team - 8 }
        x = min(x, vf.maxX - size.width - 4)
        let y = min(max(vf.minY + 4, f.minY + 4), vf.maxY - size.height - 4)
        _ = u
        activityPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func toggleChat() { chatPanel.isVisible ? closeChat() : openChat() }
    func openChat() {
        model.chatSid = model.selectedSid ?? model.sessions.first?.sid
        chat.attachSession()
        if model.chatStatus == nil { model.chatStatus = chat.status }
        model.chatOpen = true
        activityPanel.orderOut(nil)
        chatPanel.orderFrontRegardless(); positionChat()
        NSApp.activate(ignoringOtherApps: true)
        chatPanel.makeKeyAndOrderFront(nil)
        chat.focusTick += 1
        DispatchQueue.main.async { self.positionChat() }
    }
    func closeChat() {
        chat.setListening(false); chatPanel.orderOut(nil); model.chatOpen = false
    }

    // MARK: hotkey (⌃⌥Space)
    func registerHotKey() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { AppDelegate.shared.toggleChat() }; return noErr
        }, 1, &spec, nil, nil)
        let id = EventHotKeyID(signature: OSType(0x434C4144), id: 1)
        RegisterEventHotKey(UInt32(kVK_Space), UInt32(controlKey | optionKey), id, GetApplicationEventTarget(), 0, &hotKey)
    }

    // MARK: menu
    func buildMenu() -> NSMenu {
        let m = NSMenu()
        func add(_ t: String, _ sel: Selector, key: String = "", on: Bool = false) -> NSMenuItem {
            let i = NSMenuItem(title: t, action: sel, keyEquivalent: key); i.target = self; i.state = on ? .on : .off; m.addItem(i); return i
        }
        _ = add("Open \(PRODUCT_NAME)…", #selector(openMainAction))
        _ = add("Ask \(PRODUCT_NAME)…   ⌃⌥Space", #selector(menuChat))
        m.addItem(.separator())
        let connected = HookInstaller.isInstalled
        _ = add(connected ? "Connected to Claude Code" : "Connect to Claude Code…", #selector(connectAction), on: connected)
        _ = add("Disconnect and remove hooks", #selector(disconnectAction))
        _ = add("Chat settings…", #selector(aiSettings))
        _ = add("Play sounds", #selector(toggleSounds), on: soundsOn)
        _ = add("Show latest message in hover card", #selector(toggleLatest), on: model.showLatest)
        let size = NSMenu()
        for (name, v) in [("Small", 7.0), ("Medium", 10.0), ("Large", 14.0)] {
            let i = NSMenuItem(title: name, action: #selector(setScale(_:)), keyEquivalent: ""); i.target = self; i.tag = Int(v)
            i.state = Int(model.scale) == Int(v) ? .on : .off; size.addItem(i)
        }
        let sizeItem = NSMenuItem(title: "Size", action: nil, keyEquivalent: ""); sizeItem.submenu = size; m.addItem(sizeItem)
        var login = false
        if #available(macOS 13.0, *) { login = SMAppService.mainApp.status == .enabled }
        _ = add("Launch at login", #selector(toggleLogin), on: login)
        _ = add("Reset position", #selector(resetAction))
        m.addItem(.separator())
        if case .available(let v) = updater.state { _ = add("Update to \(v)…", #selector(installUpdate)) }
        else { _ = add("Check for Updates…", #selector(checkUpdates)) }
        _ = add("Quit \(PRODUCT_NAME)", #selector(quit), key: "q")
        return m
    }
    @objc func menuChat() { openChat() }
    @objc func checkUpdates() { updater.check(manual: true); showMain(.settings) }
    @objc func installUpdate() { updater.install() }
    @objc func resetAction() { resetPosition() }
    @objc func toggleSounds() { soundsOn.toggle(); item.menu = buildMenu() }
    @objc func toggleLatest() { model.showLatest.toggle(); if !model.showLatest { watcher.stop() }; item.menu = buildMenu() }
    @objc func setScale(_ s: NSMenuItem) {
        model.scale = Double(s.tag); UserDefaults.standard.set(model.scale, forKey: "scale"); item.menu = buildMenu()
        fitPanel(); positionChat()
    }
    @objc func toggleLogin() {
        if #available(macOS 13.0, *) {
            do { if SMAppService.mainApp.status == .enabled { try SMAppService.mainApp.unregister() } else { try SMAppService.mainApp.register() } }
            catch { alert("Couldn't change launch at login", error.localizedDescription) }
        } else {
            let enable = !UserDefaults.standard.bool(forKey: "loginItem")
            if SMLoginItemSetEnabled(BUNDLE_ID as CFString, enable) {
                UserDefaults.standard.set(enable, forKey: "loginItem")
            }
        }
        item.menu = buildMenu()
    }
    @objc func aiSettings() { showMain(.settings) }
    @objc func connectAction() { showMain(HookInstaller.isInstalled ? .settings : .home) }
    @objc func openMainAction() { showMain(nil) }
    @objc func openSettingsAction() { showMain(.settings) }

    func showMain(_ pane: AppState.Pane?) {
        if let pane { appState.pane = pane }
        appState.refresh()
        NSApp.activate(ignoringOtherApps: true)
        mainWindow.makeKeyAndOrderFront(nil)
        // Launched at login or from a script, macOS may refuse activation; still put the window on screen.
        mainWindow.orderFrontRegardless()
    }
    func rebuildMenu() { item.menu = buildMenu() }
    func applyScale(_ v: Double) {
        model.scale = v; UserDefaults.standard.set(v, forKey: "scale"); item.menu = buildMenu()
        fitPanel(); positionChat(); appState.objectWillChange.send()
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMain(nil) }
        return true
    }

    /// Standard app menu, so ⌘, ⌘W ⌘Q and copy/paste (for the API key) work.
    func buildMainMenu() -> NSMenu {
        let main = NSMenu()
        let appItem = NSMenuItem(); main.addItem(appItem)
        let appMenu = NSMenu()
        appMenu.addItem(withTitle: "About \(PRODUCT_NAME)", action: #selector(openAboutAction), keyEquivalent: "").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Settings…", action: #selector(openSettingsAction), keyEquivalent: ",").target = self
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide \(PRODUCT_NAME)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        appMenu.addItem(withTitle: "Quit \(PRODUCT_NAME)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = appMenu
        let editItem = NSMenuItem(); main.addItem(editItem)
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        editItem.submenu = edit
        let winItem = NSMenuItem(); main.addItem(winItem)
        let win = NSMenu(title: "Window")
        win.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        win.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        winItem.submenu = win
        NSApp.windowsMenu = win
        return main
    }
    @objc func openAboutAction() { showMain(.about) }
    @objc func disconnectAction() {
        do { try HookInstaller.remove() } catch { alert("Couldn't disconnect", error.localizedDescription) }
        item.menu = buildMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }


    func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.regular)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
