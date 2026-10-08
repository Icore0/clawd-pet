import AppKit

/// "Jump to session": brings the app that hosts a Claude Code session forward, and the exact tab where the host allows it.
/// Each host gets the honest best it supports; `Result.note` says when the exact tab couldn't be picked.
enum Jump {
    struct Result { var ok: Bool; var note: String }

    static let terminal = "com.apple.Terminal"
    static let iterm = "com.googlecode.iterm2"
    static let editors: [String: String] = [
        "com.microsoft.VSCode": "VS Code",
        "com.microsoft.VSCodeInsiders": "VS Code Insiders",
        "com.todesktop.230313mzl4w4u92": "Cursor",
        "com.exafunction.windsurf": "Windsurf",
    ]

    static func hostName(_ s: SessionPet) -> String {
        if let running = NSRunningApplication.runningApplications(withBundleIdentifier: s.hostBundleId).first, let n = running.localizedName { return n }
        if !s.hostApp.isEmpty { return ((s.hostApp as NSString).lastPathComponent as NSString).deletingPathExtension }
        return "the app"
    }

    /// Terminal and iTerm2 need Automation permission. The app explains why once before macOS asks.
    static func needsAutomation(_ s: SessionPet) -> Bool { (s.hostBundleId == terminal || s.hostBundleId == iterm) && !s.tty.isEmpty }

    static func go(_ s: SessionPet) -> Result {
        let id = s.hostBundleId
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: id).first
        if id.isEmpty || running == nil {
            if !s.cwd.isEmpty, FileManager.default.fileExists(atPath: s.cwd) {
                NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: s.cwd)
                return Result(ok: false, note: id.isEmpty ? "Don't know where this session runs; opened its folder" : "\(hostName(s)) isn't running; opened the folder")
            }
            return Result(ok: false, note: "Couldn't find where this session runs")
        }
        let name = hostName(s)
        if (id == terminal || id == iterm) && !s.tty.isEmpty {
            if selectTab(app: id, tty: s.tty) { return Result(ok: true, note: "") }
            running?.activate()
            return Result(ok: false, note: "Brought \(name) forward; couldn't pick the tab")
        }
        if editors[id] != nil, !s.cwd.isEmpty, let app = URL(string: "file://" + s.hostApp.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed)!) {
            // Opening the folder with the editor focuses the window that already has it (VS Code family behaviour).
            let config = NSWorkspace.OpenConfiguration()
            config.activates = true
            NSWorkspace.shared.open([URL(fileURLWithPath: s.cwd)], withApplicationAt: app, configuration: config)
            return Result(ok: true, note: "")
        }
        if id == claudeDesktop, !s.sid.isEmpty, let url = desktopLink(s) {
            // Claude Code's own `/desktop` handoff opens a session in the Claude app with this link.
            NSWorkspace.shared.open(url)
            return Result(ok: true, note: "")
        }
        running?.activate()
        return Result(ok: false, note: "Brought \(name) forward; couldn't pick the session")
    }

    static let claudeDesktop = "com.anthropic.claudefordesktop"

    /// `claude://resume?session=<id>&cwd=<path>`, the link Claude Code's `/desktop` command uses.
    static func desktopLink(_ s: SessionPet) -> URL? {
        var c = URLComponents()
        c.scheme = "claude"; c.host = "resume"
        c.queryItems = [URLQueryItem(name: "session", value: s.sid)] + (s.cwd.isEmpty ? [] : [URLQueryItem(name: "cwd", value: s.cwd)])
        return c.url
    }

    /// AppleScript selects the window and tab whose tty matches. Runs in-process; macOS asks for Automation access once.
    static func selectTab(app: String, tty: String) -> Bool {
        let safe = tty.replacingOccurrences(of: "\"", with: "")
        let src: String
        if app == terminal {
            src = """
            tell application id "com.apple.Terminal"
              repeat with w in windows
                repeat with t in tabs of w
                  if tty of t is "\(safe)" then
                    set selected of t to true
                    set index of w to 1
                    activate
                    return "ok"
                  end if
                end repeat
              end repeat
            end tell
            return "missing"
            """
        } else {
            src = """
            tell application id "com.googlecode.iterm2"
              repeat with w in windows
                repeat with t in tabs of w
                  repeat with s in sessions of t
                    if tty of s is "\(safe)" then
                      select s
                      select t
                      select w
                      activate
                      return "ok"
                    end if
                  end repeat
                end repeat
              end repeat
            end tell
            return "missing"
            """
        }
        var err: NSDictionary?
        let out = NSAppleScript(source: src)?.executeAndReturnError(&err)
        return err == nil && out?.stringValue == "ok"
    }
}
