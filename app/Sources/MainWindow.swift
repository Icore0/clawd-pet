import AppKit
import ServiceManagement
import SwiftUI

/// What the main window shows. `@Published` (not `@State`) so it builds with plain swiftc.
final class AppState: ObservableObject {
    enum Pane: String, CaseIterable, Identifiable {
        case home = "Home", sessions = "Sessions", animations = "Animations", settings = "Settings", about = "About"
        var id: String { rawValue }
        var icon: String {
            switch self {
            case .home: return "house"
            case .sessions: return "rectangle.stack"
            case .animations: return "sparkles"
            case .settings: return "gearshape"
            case .about: return "info.circle"
            }
        }
    }
    @Published var pane: Pane = .home
    @Published var connected = HookInstaller.isInstalled
    @Published var connectError = ""
    @Published var keyDraft = ""
    @Published var modelDraft = ""
    @Published var provider = Provider.current
    @Published var preview = "breathe"
    weak var delegate: AppDelegate?

    /// Where the running app lives. A quarantined app opened from Downloads or the disk image runs from a
    /// temporary, read-only copy (App Translocation); hooks pointing there would break, so Connect waits for a move.
    var appPath: String { Bundle.main.bundlePath }
    var translocated: Bool { appPath.contains("/AppTranslocation/") }
    var inApplications: Bool {
        appPath.hasPrefix("/Applications/") || appPath.hasPrefix(NSHomeDirectory() + "/Applications/")
    }
    var locationOK: Bool { inApplications && !translocated }

    func refresh() {
        let now = HookInstaller.isInstalled
        if now != connected { connected = now }
    }

    func connect() {
        connectError = ""
        if translocated {
            connectError = "macOS is running Wigglet from a temporary copy. Move it to Applications, open it from there, then connect."
            return
        }
        do { try HookInstaller.install(); connected = HookInstaller.isInstalled }
        catch { connectError = error.localizedDescription }
        delegate?.rebuildMenu()
    }

    func disconnect() {
        do { try HookInstaller.remove(); connected = HookInstaller.isInstalled }
        catch { connectError = error.localizedDescription }
        delegate?.rebuildMenu()
    }
}

/// Pixel Wigglet drawn with the same renderer as the floating pet. `name` picks the clip, `t` the moment in it.
struct MascotView: View {
    let model: PetModel
    var name = "breathe"
    var t: Double = 0
    var cell: Double = 6
    var body: some View {
        Canvas { ctx, size in
            let r = Renderer(m: model)
            let pose = r.pose(name, quirk: 0, local: -1, t: t, age: t, now: Date(timeIntervalSinceReferenceDate: t))
            let px = cell / 2
            let ox = (Double(size.width) - 24 * px) / 2 + Double(pose.dx) * px
            let oy = Double(size.height) - 18 * px - Double(pose.lift) * px
            let pen = Pen(ctx, u: px, ox: ox, oy: oy)
            r.paintSprite(pen, pose, name, t, t)
            r.paintEffects(pen, name, pose, frame: r.clipFrame(name, age: t), t: t, session: nil, now: Date(timeIntervalSinceReferenceDate: t))
        }
        .accessibilityLabel("Wigglet, \(name)")
    }
}

/// Animates a MascotView at 12 fps while it is on screen.
struct LiveMascot: View {
    let model: PetModel
    var name = "breathe"
    var cell: Double = 6
    /// Loops run on (their own data decides what repeats); one-shots replay after a short rest.
    func previewTime(_ d: Date) -> Double {
        let t = d.timeIntervalSinceReferenceDate
        let frames = Double(AnimationData.frames[AnimationCatalog.resolve(name)]?.count ?? 12) / 12
        return AnimationCatalog.byId(name).loop ? t.truncatingRemainder(dividingBy: 3600) : t.truncatingRemainder(dividingBy: frames + 0.8)
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { tl in
            MascotView(model: model, name: name, t: previewTime(tl.date), cell: cell)
        }
    }
}

/// Short host label for a session ("CLAUDE APP", "TERMINAL", ...).
func hostLabel(_ s: SessionPet) -> String {
    switch s.hostBundleId {
    case "com.anthropic.claudefordesktop": return "Claude app"
    case Jump.terminal: return "Terminal"
    case Jump.iterm: return "iTerm2"
    case "": return ""
    default: return Jump.editors[s.hostBundleId] ?? Jump.hostName(s)
    }
}

struct MainView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(model: model, state: state)
            Rectangle().fill(W.soft).frame(width: 1)
            GeometryReader { geo in
            ScrollView {
                Group {
                    switch state.pane {
                    case .home: HomePane(model: model, state: state)
                    case .sessions: SessionsPane(model: model, state: state)
                    case .animations: AnimationsPane(model: model, state: state)
                    case .settings: SettingsPane(model: model, state: state)
                    case .about: AboutPane(model: model)
                    }
                }
                // Content grows with the window (full screen included), with margins that grow too.
                .padding(.horizontal, max(44, geo.size.width * 0.06)).padding(.top, 56).padding(.bottom, 40)
                .frame(maxWidth: 1500, alignment: .leading)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            }
        }
        .background(W.bg)
        .preferredColorScheme(.dark)
        .frame(minWidth: 860, minHeight: 580)
    }
}

struct Sidebar: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                MascotView(model: model, name: "breathe", t: 0, cell: 2).frame(width: 30, height: 22)
                Text("wigglet").font(W.mono(14, .medium)).foregroundStyle(W.ink)
            }
            .padding(.top, 46).padding(.horizontal, 22).padding(.bottom, 26)
            Hairline()
            ForEach(Array(AppState.Pane.allCases.enumerated()), id: \.offset) { i, pane in
                let on = state.pane == pane
                Button { state.pane = pane } label: {
                    HStack(spacing: 12) {
                        Rectangle().fill(on ? W.clay : Color.clear).frame(width: 2, height: 18)
                        Text(String(format: "%02d", i + 1)).font(W.mono(10.5)).foregroundStyle(on ? W.clay : W.ink4)
                        Text(pane.rawValue.uppercased()).font(W.mono(12, .medium)).tracking(0.6).foregroundStyle(on ? W.ink : W.ink3)
                        Spacer()
                        Keycap(text: "⌘\(i + 1)", active: on)
                        if pane == .sessions && !model.sessions.isEmpty {
                            Text("\(model.sessions.count)").font(W.mono(10.5)).foregroundStyle(W.ink3)
                        }
                    }
                    .padding(.trailing, 18).frame(height: 46)
                    .background(on ? W.panel : Color.clear)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(KeyEquivalent(Character("\(i + 1)")), modifiers: .command)
                Hairline()
            }
            Spacer()
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 8) {
                    Rectangle().fill(state.connected ? W.ok : W.clay).frame(width: 7, height: 7)
                    MonoLabel(text: state.connected ? "Connected" : (HookInstaller.isStale ? "Reconnect" : "Not connected"), color: state.connected ? W.ink2 : W.clay, size: 10.5)
                }
                MonoLabel(text: "Unofficial fan project", color: W.ink4, size: 9.5)
            }
            .padding(22)
        }
        .frame(width: 232)
        .background(W.bg)
    }
}

// MARK: Home

struct HomePane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var allDone: Bool { state.locationOK && state.connected && !model.sessions.isEmpty }

    func status(_ done: Bool, _ warn: Bool = false) -> some View {
        Group {
            if done { Chip(text: "Done", color: W.ok) }
            else if warn { Chip(text: "Fix this", color: W.clay) }
            else { Chip(text: "To do", color: W.ink3) }
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 14) {
                    MonoLabel(text: "01 / Setup", color: W.clay)
                    Heading(text: allDone ? "You're all set." : "Set up Wigglet.", size: 46)
                    Text("Three steps. Each one checks itself.").font(W.sans(15)).foregroundStyle(W.ink3)
                }
                Spacer()
                LiveMascot(model: model, name: allDone ? "done" : (state.connected ? "breathe" : "ask"), cell: 7).frame(width: 120, height: 100)
            }
            .padding(.bottom, 34)
            Hairline(strong: true)

            WRow(number: "01", title: "Keep Wigglet in Applications",
                 detail: state.locationOK ? "Running from \(state.appPath)"
                    : (state.translocated
                       ? "macOS is running a temporary copy that Claude Code can't reach later. Drag Wigglet into Applications and open it from there."
                       : "Hooks point at this exact copy, so move Wigglet into Applications first, then open it from there.")) {
                HStack(spacing: 10) {
                    if !state.locationOK {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: state.appPath)]) }
                            .buttonStyle(WButton(kind: .line, small: true))
                    }
                    status(state.locationOK, !state.locationOK)
                }
            }
            WRow(number: "02", title: "Connect to Claude Code",
                 detail: state.connected ? "Hooks are in ~/.claude/settings.json. The original was backed up first."
                    : (HookInstaller.isStale ? "Your hooks still point at an older copy of Wigglet, so no activity reaches this one. Reconnect to fix it."
                       : "Adds a few hook entries to ~/.claude/settings.json and saves a backup beside it. Replaces hooks left by older builds.")) {
                HStack(spacing: 10) {
                    if !state.connected {
                        Button(HookInstaller.isStale ? "Reconnect" : "Connect") { state.connect() }.buttonStyle(WButton(kind: .solid, small: true)).disabled(state.translocated)
                    }
                    status(state.connected)
                }
            }
            if !state.connectError.isEmpty {
                Text(state.connectError).font(W.sans(12)).foregroundStyle(W.clay).padding(.vertical, 8)
            }
            WRow(number: "03", title: "Find your sessions",
                 detail: model.sessions.isEmpty
                    ? "Looking for sessions you've used in the last \(HideAfter.options.first { $0.0 == HideAfter.minutes }?.1 ?? "3h"). Open one in the Claude app, a terminal, VS Code or Cursor."
                    : (model.sessions.count == 1 ? "Found \(model.sessionTag(model.sessions[0])) in \(hostLabel(model.sessions[0]))." : "Found \(model.sessions.count) sessions, including ones that were already open.")) {
                HStack(spacing: 10) {
                    if !model.sessions.isEmpty {
                        Button("Open sessions") { state.pane = .sessions }.buttonStyle(WButton(kind: .line, small: true))
                    } else if state.connected {
                        ProgressView().controlSize(.small).tint(W.clay)
                    }
                    status(!model.sessions.isEmpty)
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                MonoLabel(text: "Works with")
                HStack(spacing: 0) {
                    ForEach(["Claude app", "Terminal", "iTerm2", "VS Code", "Cursor"], id: \.self) { h in
                        Text(h).font(W.sans(13)).foregroundStyle(W.ink2)
                            .padding(.horizontal, 14).frame(height: 34)
                            .overlay(Rectangle().stroke(W.soft, lineWidth: 1))
                    }
                }
                Text("Any Claude Code session that reads ~/.claude/settings.json, including the Code tab in the Claude desktop app.")
                    .font(W.sans(12)).foregroundStyle(W.ink4)
            }
            .padding(.top, 34)
        }
    }
}

// MARK: Sessions

struct SessionsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    func status(_ mood: String) -> (String, Color) {
        switch mood {
        case "waiting": return ("needs you", W.clay)
        case "working": return ("working", W.ok)
        case "done": return ("done", W.ink2)
        case "stalled": return ("quiet", W.ink4)
        default: return ("idle", W.ink4)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: "02 / Sessions", color: W.clay).padding(.bottom, 14)
            Heading(text: model.sessions.isEmpty ? "No sessions yet." : "Every session, one Wigglet.", size: 46).padding(.bottom, 34)
            Hairline(strong: true)
            if model.sessions.isEmpty {
                HStack(spacing: 22) {
                    LiveMascot(model: model, name: "sleep", cell: 6).frame(width: 110, height: 90)
                    VStack(alignment: .leading, spacing: 10) {
                        Text(state.connected ? "Start Claude Code anywhere and its Wigglet shows up here." : "Connect to Claude Code first.")
                            .font(W.sans(15)).foregroundStyle(W.ink2)
                        if !state.connected { Button("Set up") { state.pane = .home }.buttonStyle(WButton(kind: .solid, small: true)) }
                    }
                }
                .padding(.vertical, 30)
            } else {
                ForEach(model.sessions.sorted { ($0.mood == "waiting" ? 1 : 0, $0.ts) > ($1.mood == "waiting" ? 1 : 0, $1.ts) }) { s in
                    let st = status(s.mood)
                    VStack(spacing: 0) {
                        HStack(spacing: 18) {
                            Rectangle().fill(s.mood == "waiting" ? W.clay : Color.clear).frame(width: 2, height: 44)
                            MascotView(model: model, name: s.mood == "waiting" ? "ask" : (s.mood == "working" ? "edit" : "breathe"), t: 0.4, cell: 3)
                                .frame(width: 48, height: 36)
                            VStack(alignment: .leading, spacing: 5) {
                                HStack(spacing: 10) {
                                    Text(model.sessionTag(s)).font(W.sans(18)).foregroundStyle(W.ink)
                                    Chip(text: st.0, color: st.1)
                                }
                                Text(s.say.isEmpty ? s.cwd : (s.delta.isEmpty ? s.say : "\(s.say)  \(s.delta)"))
                                    .font(W.sans(13)).foregroundStyle(W.ink3).lineLimit(1).truncationMode(.middle)
                            }
                            Spacer(minLength: 10)
                            VStack(alignment: .trailing, spacing: 5) {
                                MonoLabel(text: hostLabel(s), color: W.ink2, size: 10.5)
                                MonoLabel(text: activeAgo(s.ts), color: W.ink4, size: 10)
                            }
                            Button("Jump ↗") { state.delegate?.jump(s) }.buttonStyle(WButton(kind: .line, small: true))
                                .help(s.hostApp.isEmpty ? "Jump to this session" : "Jump to \(Jump.hostName(s))")
                        }
                        .padding(.vertical, 14)
                        Hairline()
                    }
                }
            }
        }
    }
}

// MARK: Animations

struct AnimationsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var clips: [Animation] { AnimationCatalog.all.filter { $0.id != "glide" } }
    var body: some View {
        let a = AnimationCatalog.byId(state.preview)
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: "03 / Animations", color: W.clay).padding(.bottom, 14)
            Heading(text: "\(clips.count) clips. Pick one.", size: 46).padding(.bottom, 30)
            HStack(alignment: .center, spacing: 28) {
                LiveMascot(model: model, name: a.id, cell: 10).frame(width: 260, height: 190)
                    .background(W.raised).overlay(Rectangle().stroke(W.soft, lineWidth: 1))
                VStack(alignment: .leading, spacing: 10) {
                    Text(a.id).font(W.sans(26)).tracking(-0.6).foregroundStyle(W.ink)
                    Text(a.detected).font(W.sans(13)).foregroundStyle(W.ink3).fixedSize(horizontal: false, vertical: true)
                    HStack(spacing: 8) {
                        Chip(text: String(format: "%.1f s", a.duration))
                        Chip(text: a.loop ? "loops" : "plays once")
                        Chip(text: "priority \(a.priority)")
                    }
                }
            }
            .padding(.bottom, 28)
            let cols = [GridItem(.adaptive(minimum: 140), spacing: 0)]
            LazyVGrid(columns: cols, spacing: 0) {
                ForEach(clips, id: \.id) { c in
                    let on = state.preview == c.id
                    Button { state.preview = c.id } label: {
                        VStack(spacing: 6) {
                            MascotView(model: model, name: c.id, t: Double(AnimationData.clips[c.id]?.frameCount ?? 12) / 24, cell: 4).frame(height: 58)
                            Text(c.id).font(W.mono(10.5)).foregroundStyle(on ? W.clay : W.ink3).lineLimit(1).minimumScaleFactor(0.6)
                        }
                        .padding(.vertical, 12).padding(.horizontal, 6)
                        .frame(maxWidth: .infinity)
                        .background(on ? W.panel : Color.clear)
                        .overlay(Rectangle().stroke(on ? W.clay : W.soft, lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

// MARK: Settings

struct SettingsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    func group(_ title: String) -> some View {
        MonoLabel(text: title).padding(.top, 30).padding(.bottom, 4)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: "04 / Settings", color: W.clay).padding(.bottom, 14)
            Heading(text: "Settings.", size: 46).padding(.bottom, 10)

            group("Claude Code")
            Hairline(strong: true)
            WRow(title: state.connected ? "Connected" : (HookInstaller.isStale ? "Needs reconnecting" : "Not connected"),
                 detail: state.connected ? "Hooks live in ~/.claude/settings.json."
                    : (HookInstaller.isStale ? "The hooks point at an older copy of Wigglet. Reconnect so this one gets the activity." : "Wigglet can't see your sessions until it's connected.")) {
                HStack(spacing: 10) {
                    Button("Show file") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settingsPath)]) }
                        .buttonStyle(WButton(kind: .line, small: true))
                    if state.connected { Button("Disconnect") { state.disconnect() }.buttonStyle(WButton(kind: .line, small: true)) }
                    else { Button(HookInstaller.isStale ? "Reconnect" : "Connect") { state.connect() }.buttonStyle(WButton(kind: .solid, small: true)).disabled(state.translocated) }
                }
            }
            if !state.connectError.isEmpty { Text(state.connectError).font(W.sans(12)).foregroundStyle(W.clay).padding(.vertical, 6) }

            group("Wigglets")
            Hairline(strong: true)
            WRow(title: "Size", detail: "How big each Wigglet is on your desktop.") {
                Segmented(options: [(7, "Small"), (10, "Medium"), (14, "Large")],
                          selection: Binding(get: { Int(model.scale) }, set: { state.delegate?.applyScale(Double($0)) }))
            }
            WRow(title: "Sounds", detail: "A ping when a session needs you, a chime when one finishes.") {
                SquareToggle(isOn: Binding(get: { state.delegate?.soundsOn ?? false }, set: { state.delegate?.soundsOn = $0; state.objectWillChange.send() }), label: "Sounds")
            }
            WRow(title: "Latest message in hover card", detail: "Read from the local transcript, shown only, never stored or sent.") {
                SquareToggle(isOn: Binding(get: { model.showLatest }, set: { model.showLatest = $0; state.objectWillChange.send(); state.delegate?.rebuildMenu() }), label: "Latest message")
            }
            WRow(title: "One Wigglet", detail: "One character for every session. It shows whichever needs you; hover it to see them all.") {
                SquareToggle(isOn: Binding(get: { model.oneWigglet }, set: { model.oneWigglet = $0; model.objectWillChange.send(); state.objectWillChange.send() }), label: "One Wigglet")
            }
            WRow(title: "Hide sessions untouched for", detail: "Sessions you haven't worked in for this long leave the team. They come back when you use them.") {
                Segmented(options: HideAfter.options, selection: Binding(get: { HideAfter.minutes }, set: { HideAfter.minutes = $0; model.discovery.invalidate(); state.objectWillChange.send() }))
            }
            WRow(title: "Position", detail: "Put the team back in the bottom-right corner.") {
                Button("Reset") { state.delegate?.resetPosition() }.buttonStyle(WButton(kind: .line, small: true))
            }

            group("Updates")
            Hairline(strong: true)
            UpdateRows()

            group("Startup")
            Hairline(strong: true)
            WRow(title: "Open at login", detail: "Wigglet starts with your Mac.") {
                SquareToggle(isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in state.delegate?.toggleLogin(); state.objectWillChange.send() }), label: "Open at login")
            }

            group("Chat")
            Hairline(strong: true)
            WRow(title: "Who answers", detail: state.provider.detail) {
                Menu {
                    ForEach(Provider.allCases) { p in
                        Button(p.label) { Provider.current = p; state.provider = p; state.keyDraft = ""; state.modelDraft = "" }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Text(state.provider.label.uppercased()).font(W.mono(11, .semibold)).tracking(0.5).foregroundStyle(W.ink)
                        Image(systemName: "chevron.down").font(.system(size: 9, weight: .bold)).foregroundStyle(W.ink3)
                    }
                    .padding(.horizontal, 11).frame(height: 28).overlay(Rectangle().stroke(W.line, lineWidth: 1))
                }
                .menuStyle(.button).buttonStyle(.plain).menuIndicator(.hidden).fixedSize()
            }
            if state.provider.needsKey {
                let saved = KeychainStore.load(state.provider) != nil
                WRow(title: "\(state.provider.label) key", detail: saved ? "Saved in the macOS Keychain, on this Mac only." : "Stored in the macOS Keychain. Sent only to \(state.provider.label).") {
                    HStack(spacing: 8) {
                        SecureField(state.provider.keyHint, text: $state.keyDraft)
                            .textFieldStyle(.plain).font(W.mono(12)).foregroundStyle(W.ink)
                            .padding(.horizontal, 10).frame(width: 200, height: 28)
                            .background(W.raised).overlay(Rectangle().stroke(W.line, lineWidth: 1))
                        Button("Save") {
                            let typed = state.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                            if !typed.isEmpty && KeychainStore.save(typed, for: state.provider) { state.keyDraft = ""; state.objectWillChange.send() }
                        }.buttonStyle(WButton(kind: .solid, small: true)).disabled(state.keyDraft.isEmpty)
                        if saved { Button("Remove") { KeychainStore.delete(state.provider); state.objectWillChange.send() }.buttonStyle(WButton(kind: .line, small: true)) }
                    }
                }
            }
            if state.provider != .claude {
                WRow(title: "Model", detail: "Any model id \(state.provider.label) accepts. Empty means \(state.provider.defaultModel).") {
                    TextField(state.provider.model, text: Binding(get: { state.modelDraft.isEmpty ? state.provider.model : state.modelDraft },
                                                                  set: { state.modelDraft = $0; state.provider.model = $0 }))
                        .textFieldStyle(.plain).font(W.mono(12)).foregroundStyle(W.ink)
                        .padding(.horizontal, 10).frame(width: 260, height: 28)
                        .background(W.raised).overlay(Rectangle().stroke(W.line, lineWidth: 1))
                }
            }
        }
    }
}

func activeAgo(_ ts: Double) -> String {
    let m = Int((Date().timeIntervalSince1970 * 1000 - ts) / 60_000)
    if m < 1 { return "active now" }
    return m < 60 ? "active \(m)m ago" : "active \(m / 60)h ago"
}

/// Updates arrive only when a new version is published on GitHub, and only if its signature checks out.
struct UpdateRows: View {
    @ObservedObject var updater = Updater.shared
    var body: some View {
        WRow(title: "Version \(Updater.current)", detail: updater.label) {
            switch updater.state {
            case .available: Button("Update now") { updater.install() }.buttonStyle(WButton(kind: .clay, small: true))
            case .checking, .installing: ProgressView().controlSize(.small).tint(W.clay)
            default: Button("Check now") { updater.check(manual: true) }.buttonStyle(WButton(kind: .line, small: true))
            }
        }
        WRow(title: "Install updates automatically", detail: "New versions install and Wigglet reopens by itself. Off: you'll see an Update button here and in the menu.") {
            SquareToggle(isOn: Binding(get: { Updater.auto }, set: { Updater.auto = $0; updater.objectWillChange.send() }), label: "Install updates automatically")
        }
    }
}

// MARK: About

struct AboutPane: View {
    let model: PetModel
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            MonoLabel(text: "05 / About", color: W.clay).padding(.bottom, 14)
            HStack(alignment: .center, spacing: 30) {
                VStack(alignment: .leading, spacing: 14) {
                    Heading(text: "Wigglet", size: 64)
                    Text("One Wigglet for every Claude Code session.").font(W.sans(16)).foregroundStyle(W.ink3)
                }
                Spacer()
                LiveMascot(model: model, name: "hello", cell: 10).frame(width: 160, height: 130)
            }
            .padding(.bottom, 34)
            Hairline(strong: true)
            WRow(title: "Version", detail: "") {
                MonoLabel(text: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0", color: W.ink2)
            }
            WRow(title: "Source", detail: "github.com/Icore0/wigglet") {
                Button("Open ↗") { NSWorkspace.shared.open(URL(string: "https://github.com/Icore0/wigglet")!) }
                    .buttonStyle(WButton(kind: .line, small: true))
            }
            WRow(title: "License", detail: "Source available. All rights reserved until a license is announced.") { EmptyView() }
            Text("Credits: Claude, Claude Code and the original mascot design are by Anthropic. Wigglet is an unofficial fan tribute, not affiliated with, sponsored by, or endorsed by Anthropic. \"Claude\" and \"Anthropic\" are trademarks of Anthropic, PBC. Free, no ads, no data collection.")
                .font(W.sans(12)).foregroundStyle(W.ink4).padding(.top, 24).fixedSize(horizontal: false, vertical: true)
        }
    }
}
