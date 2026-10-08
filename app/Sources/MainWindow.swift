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
    @Published var keySaved = KeychainStore.load() != nil
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
            let ox = (Double(size.width) - 12 * cell) / 2 + Double(pose.dx) * cell
            let oy = Double(size.height) - 9 * cell - Double(pose.lift) * cell
            let pen = Pen(ctx, u: cell, ox: ox, oy: oy)
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
    var body: some View {
        TimelineView(.periodic(from: .now, by: 1.0 / 12)) { tl in
            MascotView(model: model, name: name, t: tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: max(0.5, AnimationCatalog.byId(name).duration)), cell: cell)
        }
    }
}

struct MainView: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState

    var body: some View {
        NavigationSplitView {
            List(AppState.Pane.allCases, selection: Binding(get: { state.pane }, set: { if let p = $0 { state.pane = p } })) { pane in
                Label(pane.rawValue, systemImage: pane.icon).tag(pane)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            Group {
                switch state.pane {
                case .home: HomePane(model: model, state: state)
                case .sessions: SessionsPane(model: model, state: state)
                case .animations: AnimationsPane(model: model, state: state)
                case .settings: SettingsPane(model: model, state: state)
                case .about: AboutPane(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .frame(minWidth: 760, minHeight: 520)
    }
}

// MARK: Home: three checked steps, live

struct StepRow<Content: View>: View {
    let number: Int
    let title: String
    let done: Bool
    var warn = false
    @ViewBuilder var content: Content
    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle().fill(done ? Color.green.opacity(0.18) : (warn ? Color.orange.opacity(0.18) : Color.secondary.opacity(0.12)))
                if done { Image(systemName: "checkmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.green) }
                else if warn { Image(systemName: "exclamationmark").font(.system(size: 13, weight: .bold)).foregroundStyle(.orange) }
                else { Text("\(number)").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary) }
            }
            .frame(width: 30, height: 30)
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(.system(size: 15, weight: .semibold))
                content
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.04)))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Step \(number): \(title)\(done ? ", done" : "")")
    }
}

struct HomePane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                HStack(spacing: 18) {
                    LiveMascot(model: model, name: state.connected && !model.sessions.isEmpty ? "hello" : "breathe", cell: 7)
                        .frame(width: 110, height: 90)
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Wigglet").font(.system(size: 30, weight: .bold))
                        Text("One Wigglet for every Claude Code session.").font(.system(size: 14)).foregroundStyle(.secondary)
                    }
                }
                .padding(.bottom, 4)

                StepRow(number: 1, title: "Keep Wigglet in Applications", done: state.locationOK, warn: !state.locationOK) {
                    if state.locationOK {
                        Text("Running from \(state.appPath)").font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    } else {
                        Text(state.translocated
                             ? "macOS is running a temporary copy, so Claude Code couldn't find Wigglet later. Drag Wigglet into Applications, then open it from there."
                             : "Wigglet isn't in Applications. Hooks point at this exact copy, so move it first, then open it from Applications.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Show Wigglet in Finder") { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: state.appPath)]) }
                    }
                }

                StepRow(number: 2, title: "Connect to Claude Code", done: state.connected) {
                    if state.connected {
                        Text("Hooks are in ~/.claude/settings.json. Your original was backed up first.").font(.system(size: 12)).foregroundStyle(.secondary)
                    } else {
                        Text("Adds a few hook entries to ~/.claude/settings.json and saves a backup beside it. Nothing else changes.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        Button("Connect") { state.connect() }.buttonStyle(.borderedProminent).disabled(state.translocated)
                    }
                    if !state.connectError.isEmpty {
                        Text(state.connectError).font(.system(size: 12)).foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                    }
                }

                StepRow(number: 3, title: "Start a Claude Code session", done: !model.sessions.isEmpty) {
                    if let s = model.sessions.first {
                        Text("Found \(model.sessionTag(s)). Its Wigglet is on your desktop.").font(.system(size: 12)).foregroundStyle(.secondary)
                        Button("Open Sessions") { state.pane = .sessions }
                    } else if state.connected {
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Waiting… run `claude` in any terminal, or start a new session in VS Code or the Claude app.")
                                .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                        }
                    } else {
                        Text("After connecting, start a new session. Sessions that are already running appear after their next tool call.")
                            .font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 640, alignment: .leading)
        }
    }
}

// MARK: Sessions

struct SessionsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    func status(_ mood: String) -> (String, Color) {
        switch mood {
        case "waiting": return ("needs you", .orange)
        case "working": return ("working", .green)
        case "done": return ("done", .blue)
        case "stalled": return ("quiet", .gray)
        default: return ("idle", .gray)
        }
    }
    var body: some View {
        if model.sessions.isEmpty {
            VStack(spacing: 10) {
                LiveMascot(model: model, name: "sleep", cell: 6).frame(width: 110, height: 90)
                Text("No sessions yet").font(.system(size: 17, weight: .semibold))
                Text(state.connected ? "Start Claude Code and its Wigglet appears here." : "Connect to Claude Code first.")
                    .foregroundStyle(.secondary)
                if !state.connected { Button("Set up") { state.pane = .home } }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            List {
                ForEach(model.displaySessions) { s in
                    let st = status(s.mood)
                    HStack(spacing: 14) {
                        MascotView(model: model, name: s.mood == "waiting" ? "ask" : "breathe", t: 0, cell: 3).frame(width: 46, height: 34)
                        VStack(alignment: .leading, spacing: 3) {
                            HStack(spacing: 8) {
                                Text(model.sessionTag(s)).font(.system(size: 14, weight: .semibold))
                                Text(st.0).font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 2)
                                    .background(Capsule().fill(st.1.opacity(0.16))).foregroundStyle(st.1)
                            }
                            Text(s.say.isEmpty ? s.cwd : (s.delta.isEmpty ? s.say : "\(s.say) \(s.delta)"))
                                .font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                        }
                        Spacer()
                        Text(s.toolCount == 1 ? "1 tool" : "\(s.toolCount) tools").font(.system(size: 11)).foregroundStyle(.secondary)
                        Button("Jump") { state.delegate?.jump(s) }
                            .help(s.hostApp.isEmpty ? "Jump to this session" : "Jump to \(Jump.hostName(s))")
                    }
                    .padding(.vertical, 4)
                }
            }
        }
    }
}

// MARK: Animations

struct AnimationsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var body: some View {
        HStack(spacing: 0) {
            ScrollView {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                    ForEach(AnimationCatalog.all.filter { $0.id != "glide" }, id: \.id) { a in
                        Button { state.preview = a.id } label: {
                            VStack(spacing: 4) {
                                MascotView(model: model, name: a.id, t: Double(AnimationData.clips[a.id]?.frameCount ?? 12) / 24, cell: 4)
                                    .frame(height: 64)
                                Text(a.id).font(.system(size: 11, weight: .medium)).lineLimit(1).minimumScaleFactor(0.6)
                            }
                            .padding(8)
                            .frame(maxWidth: .infinity)
                            .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .fill(state.preview == a.id ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.04)))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(16)
            }
            Divider()
            let a = AnimationCatalog.byId(state.preview)
            VStack(alignment: .leading, spacing: 10) {
                LiveMascot(model: model, name: a.id, cell: 10).frame(width: 240, height: 200)
                Text(a.id).font(.system(size: 18, weight: .semibold))
                Text(a.detected).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Text(String(format: "%.1f s · %@", a.duration, a.loop ? "loops" : "plays once")).font(.system(size: 11)).foregroundStyle(.tertiary)
                Spacer()
            }
            .padding(18)
            .frame(width: 280)
        }
    }
}

// MARK: Settings

struct SettingsPane: View {
    @ObservedObject var model: PetModel
    @ObservedObject var state: AppState
    var body: some View {
        Form {
            Section("Claude Code") {
                HStack {
                    Label(state.connected ? "Connected" : "Not connected", systemImage: state.connected ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(state.connected ? .green : .secondary)
                    Spacer()
                    if state.connected { Button("Disconnect") { state.disconnect() } }
                    else { Button("Connect") { state.connect() }.disabled(state.translocated) }
                }
                if !state.connectError.isEmpty { Text(state.connectError).foregroundStyle(.red).font(.system(size: 12)) }
                Button("Show settings.json in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: settingsPath)])
                }
            }
            Section("Wigglets") {
                Picker("Size", selection: Binding(get: { Int(model.scale) }, set: { state.delegate?.applyScale(Double($0)) })) {
                    Text("Small").tag(7); Text("Medium").tag(10); Text("Large").tag(14)
                }
                Toggle("Play sounds when a session needs you or finishes", isOn: Binding(get: { state.delegate?.soundsOn ?? false }, set: { state.delegate?.soundsOn = $0; state.objectWillChange.send() }))
                Toggle("Show latest message in hover card", isOn: Binding(get: { model.showLatest }, set: { model.showLatest = $0; state.objectWillChange.send(); state.delegate?.rebuildMenu() }))
                Button("Reset position") { state.delegate?.resetPosition() }
            }
            Section("Startup") {
                Toggle("Open Wigglet at login", isOn: Binding(get: { SMAppService.mainApp.status == .enabled }, set: { _ in state.delegate?.toggleLogin(); state.objectWillChange.send() }))
            }
            Section("Chat") {
                HStack {
                    SecureField(state.keySaved ? "OpenRouter key saved in Keychain" : "OpenRouter API key", text: Binding(get: { state.keyDraft }, set: { state.keyDraft = $0 }))
                    Button("Save") {
                        let typed = state.keyDraft.trimmingCharacters(in: .whitespacesAndNewlines)
                        if !typed.isEmpty && KeychainStore.save(typed) { state.keyDraft = ""; state.keySaved = true }
                    }.disabled(state.keyDraft.isEmpty)
                    if state.keySaved { Button("Remove") { KeychainStore.delete(); state.keySaved = false } }
                }
                Picker("Model", selection: Binding(get: { state.delegate?.chat.model ?? orModels[0].id }, set: { state.delegate?.chat.model = $0; state.objectWillChange.send() })) {
                    ForEach(orModels, id: \.id) { Text($0.label).tag($0.id) }
                }
                Toggle("Use Claude Code CLI instead (counts toward your Claude plan)", isOn: Binding(get: { state.delegate?.chat.useCLI ?? false }, set: { v in
                    state.delegate?.chat.useCLI = v; UserDefaults.standard.set(v, forKey: "useClaudeCLI"); state.objectWillChange.send()
                }))
                Text("The key stays in the macOS Keychain. Chat sends your messages and a short session summary, never file contents.")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }
}

// MARK: About

struct AboutPane: View {
    let model: PetModel
    var body: some View {
        VStack(spacing: 12) {
            LiveMascot(model: model, name: "hello", cell: 9).frame(width: 140, height: 110)
            Text("Wigglet").font(.system(size: 26, weight: .bold))
            Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0")")
                .foregroundStyle(.secondary)
            Link("github.com/Icore0/wigglet", destination: URL(string: "https://github.com/Icore0/wigglet")!)
            Text("Unofficial fan project, not affiliated with Anthropic. The mascot belongs to Anthropic.")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
            Text("Source available. All rights reserved until a license is announced.")
                .font(.system(size: 11)).foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(30)
    }
}
