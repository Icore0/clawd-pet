import AppKit
import Carbon.HIToolbox
import ServiceManagement
import SwiftUI

final class OpenRouterProbe {
    var status = "ok"
    var text = ""
    var cost = -1.0
    var done = false
}

if CommandLine.arguments.contains("--dump-catalog") {
    print(AnimationCatalog.markdown())
    exit(0)
}
if CommandLine.arguments.contains("--openrouter-selftest") {
    let key = ProcessInfo.processInfo.environment["OPENROUTER_TEST_KEY"] ?? ""
    if key.isEmpty { fputs("missing key\n", stderr); exit(2) }
    let box = OpenRouterProbe()
    OpenRouter.send(model: "openai/gpt-4o-mini", key: key, system: "test", messages: [ChatLine(role: "user", text: "hi")], onStatus: { status in
        box.status = status.rawValue
        box.done = true
    }, onDelta: { box.text += $0 }, onCost: { box.cost = $0 }, onFinish: { box.done = true })
    let deadline = Date().addingTimeInterval(25)
    while !box.done && Date() < deadline { RunLoop.current.run(until: Date().addingTimeInterval(0.05)) }
    if box.status == "ok" && box.text.isEmpty && !box.done { box.status = "timeout" }
    print("status=\(box.status) text=\(box.text) cost=\(box.cost)")
    exit(box.done ? 0 : 1)
}
if CommandLine.arguments.contains("--hook") { runHookMode() }
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
if CommandLine.arguments.contains("--selftest") {
    let home = ProcessInfo.processInfo.environment["HOME"] ?? ""
    if !home.contains("/tmp/") && !home.contains("session-pet-test") { exit(2) }
    if let problem = AnimationCatalog.runChecks() {
        print(problem)
        exit(1)
    }
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

final class DragView: NSView {
    let model: PetModel
    let clock: FrameClock
    weak var delegate: AppDelegate?
    var startMouse = NSPoint.zero, startOrigin = NSPoint.zero, moved = false
    var samples: [(NSPoint, TimeInterval)] = []

    init(model: PetModel, clock: FrameClock, delegate: AppDelegate) {
        self.model = model; self.clock = clock; self.delegate = delegate
        super.init(frame: NSRect(x: 0, y: 0, width: teamPanelWidth(count: model.sessions.count, scale: model.scale), height: canvasH))
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
        let n = min(6, max(1, model.sessions.count))
        let stride = 13 * u + 8
        let h = 10 * u + 12
        return (0..<n).map { i in NSRect(x: 8 + CGFloat(i) * stride, y: 8, width: 13 * u, height: h) }
    }
    var badgeFrame: NSRect? {
        guard model.sessions.count > 6 else { return nil }
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
    var panel: NSPanel!
    var chatPanel: ChatPanel!
    var chatHost: NSHostingView<ChatView>!
    var item: NSStatusItem!
    var glider: Glider!
    var hotKey: EventHotKeyRef?
    var activityPanel: NSPanel!
    var activityHost: NSHostingView<ActivityView>!
    var hoverWork: DispatchWorkItem?
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
        }
        if teamDemoFlag {
            model.teamDemo = true
            model.loadSessions()
        }

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: teamPanelWidth(count: model.sessions.count, scale: model.scale), height: canvasH),
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
        activityPanel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 320, height: 200), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        activityPanel.isOpaque = false; activityPanel.backgroundColor = .clear; activityPanel.hasShadow = false
        activityPanel.level = .floating; activityPanel.ignoresMouseEvents = true; activityPanel.hidesOnDeactivate = false
        activityPanel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        activityHost = NSHostingView(rootView: ActivityView(model: model))
        activityPanel.contentView = activityHost

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
        }

        if !UserDefaults.standard.bool(forKey: "askedConnect") && !HookInstaller.isInstalled {
            UserDefaults.standard.set(true, forKey: "askedConnect")
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { self.askConnect() }
        }
    }

    // MARK: positioning
    func bounds(for frame: NSRect) -> NSRect {
        let u = CGFloat(model.scale)
        let sc = NSScreen.screens.first { $0.frame.intersects(frame) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = sc.visibleFrame
        let w = panel?.frame.width ?? CGFloat(teamPanelWidth(count: model.sessions.count, scale: model.scale))
        return NSRect(x: vf.minX - w / 2 + 6 * u, y: vf.minY - 14,
                      width: vf.width - 12 * u, height: vf.height - 8 * u)
    }
    func fitPanel() {
        let w = CGFloat(teamPanelWidth(count: model.sessions.count, scale: model.scale))
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
    func savePosition() { UserDefaults.standard.set(NSStringFromPoint(panel.frame.origin), forKey: "pos") }

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
        } else { activityPanel.orderOut(nil) }
    }
    func showActivity() {
        guard !model.chatOpen, !model.isDragging, !model.isGliding, model.hover else { return }
        positionActivity(); activityPanel.orderFrontRegardless()
    }
    func positionActivity() {
        guard activityPanel != nil, activityPanel.isVisible else { return }
        activityHost.layoutSubtreeIfNeeded()
        let size = activityHost.fittingSize
        activityPanel.setContentSize(size)
        let u = CGFloat(model.scale), f = panel.frame
        let sc = NSScreen.screens.first { $0.frame.intersects(f) } ?? NSScreen.main ?? NSScreen.screens[0]
        let vf = sc.visibleFrame
        var x = f.midX - 6.5 * u - size.width - 2
        if x < vf.minX + 4 { x = f.midX + 6.5 * u + 2 }
        let y = min(max(vf.minY + 4, f.minY + 10), vf.maxY - size.height - 4)
        activityPanel.setFrameOrigin(NSPoint(x: x, y: y))
    }
    func toggleChat() { chatPanel.isVisible ? closeChat() : openChat() }
    func openChat() {
        model.chatSid = model.selectedSid ?? model.sessions.first?.sid
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
        _ = add("Ask \(PRODUCT_NAME)…   ⌃⌥Space", #selector(menuChat))
        m.addItem(.separator())
        let connected = HookInstaller.isInstalled
        _ = add(connected ? "Connected to Claude Code" : "Connect to Claude Code…", #selector(connectAction), on: connected)
        _ = add("Disconnect and remove hooks", #selector(disconnectAction))
        _ = add("AI settings", #selector(aiSettings))
        _ = add("Play sounds", #selector(toggleSounds), on: soundsOn)
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
        _ = add("Quit \(PRODUCT_NAME)", #selector(quit), key: "q")
        return m
    }
    @objc func menuChat() { openChat() }
    @objc func resetAction() { resetPosition() }
    @objc func toggleSounds() { soundsOn.toggle(); item.menu = buildMenu() }
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
    @objc func aiSettings() { showAISettings() }
    @objc func connectAction() { askConnect() }
    @objc func disconnectAction() {
        do { try HookInstaller.remove() } catch { alert("Couldn't disconnect", error.localizedDescription) }
        item.menu = buildMenu()
    }
    @objc func quit() { NSApp.terminate(nil) }

    func showAISettings() {
        let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 380, height: 168), styleMask: [.titled, .closable], backing: .buffered, defer: false)
        panel.title = "AI settings"
        let secure = NSSecureTextField(frame: NSRect(x: 16, y: 112, width: 348, height: 24))
        secure.placeholderString = "OpenRouter API key"
        let popup = NSPopUpButton(frame: NSRect(x: 16, y: 76, width: 348, height: 26))
        popup.addItems(withTitles: chat.models)
        if !chat.models.contains(chat.model) { chat.models.insert(chat.model, at: 0); popup.insertItem(withTitle: chat.model, at: 0) }
        popup.selectItem(withTitle: chat.model)
        let cli = NSButton(checkboxWithTitle: "Use Claude Code CLI instead", target: self, action: #selector(aiCLI(_:)))
        cli.frame = NSRect(x: 16, y: 46, width: 348, height: 22)
        if KeychainStore.copy() != nil && UserDefaults.standard.object(forKey: "useClaudeCLI") == nil { chat.useCLI = false }
        cli.state = chat.useCLI ? .on : .off
        let save = NSButton(title: "Save", target: self, action: #selector(aiSave(_:)))
        save.frame = NSRect(x: 280, y: 12, width: 84, height: 28)
        panel.contentView?.addSubview(secure)
        panel.contentView?.addSubview(popup)
        panel.contentView?.addSubview(cli)
        panel.contentView?.addSubview(save)
        secure.tag = 11
        popup.tag = 12
        aiPanel = panel
        panel.center()
        panel.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    @objc func aiCLI(_ button: NSButton) {
        chat.useCLI = button.state == .on
        UserDefaults.standard.set(chat.useCLI, forKey: "useClaudeCLI")
    }
    @objc func aiSave(_ button: NSButton) {
        guard let panel = aiPanel, let secure = panel.contentView?.viewWithTag(11) as? NSSecureTextField else { return }
        if let popup = panel.contentView?.viewWithTag(12) as? NSPopUpButton, let title = popup.titleOfSelectedItem {
            chat.model = title
            if !chat.models.contains(title) { chat.models.append(title) }
        }
        let typed = secure.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if !typed.isEmpty && KeychainStore.save(typed) {
            secure.stringValue = ""
            if !UserDefaults.standard.bool(forKey: "openrouterKeyNoted") {
                UserDefaults.standard.set(true, forKey: "openrouterKeyNoted")
                chat.keyNote = "The key stays in the Keychain. Messages go to OpenRouter with the session summary, not file contents."
            }
        }
        panel.orderOut(nil)
    }
    var aiPanel: NSPanel?

    func alert(_ title: String, _ text: String) {
        let a = NSAlert(); a.messageText = title; a.informativeText = text; NSApp.activate(ignoringOtherApps: true); a.runModal()
    }
    func askConnect() {
        let a = NSAlert()
        a.messageText = "Connect \(PRODUCT_NAME) to Claude Code?"
        a.informativeText = "Clawd Pet adds hook commands to ~/.claude/settings.json.\nA backup is saved beside that file."
        a.addButton(withTitle: "Connect"); a.addButton(withTitle: "Not now")
        NSApp.activate(ignoringOtherApps: true)
        if a.runModal() == .alertFirstButtonReturn {
            do { try HookInstaller.install(); model.say = "connected!"; model.clickAt = Date(); model.quip = "connected!" }
            catch { alert("Couldn't connect", error.localizedDescription) }
        }
        item.menu = buildMenu()
    }
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()
