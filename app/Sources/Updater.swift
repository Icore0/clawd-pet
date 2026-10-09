import AppKit
import CryptoKit

/// Updates come only from published GitHub Releases, so a build in progress reaches nobody until it's released.
/// Each release ships `Wigglet.zip` plus `Wigglet.zip.sig`, an Ed25519 signature made with a key that never
/// leaves the maintainer's Keychain. Nothing is installed unless that signature checks out against `publicKey`,
/// so a hijacked GitHub account or a swapped download still can't push code to anyone.
final class Updater: ObservableObject {
    enum State: Equatable { case idle, checking, upToDate, available(String), installing, failed(String) }

    static let publicKey = "jTHFNBXZA8ZoibQFmUjCUNHNmT2oPq0BcGZdycAisrY="
    static let defaultFeed = "https://api.github.com/repos/Icore0/wigglet/releases/latest"

    static let shared = Updater()
    @Published var state = State.idle { didSet { onChange() } }
    var onChange: () -> Void = {}
    @Published var notes = ""
    private var zipURL: URL?, sigURL: URL?
    private var timer: Timer?
    var onInstalled: () -> Void = {}

    /// Tests may point the feed and key elsewhere, and only when HOME is a temp dir.
    private static var testEnv: [String: String] {
        let env = ProcessInfo.processInfo.environment, home = env["HOME"] ?? ""
        return home.hasPrefix("/tmp/") || home.hasPrefix("/private/tmp/") ? env : [:]
    }
    static var feed: String { testEnv["WIGGLET_UPDATE_FEED"] ?? defaultFeed }
    static var key: String { testEnv["WIGGLET_UPDATE_PUBKEY"] ?? publicKey }

    static var current: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0" }
    static var auto: Bool {
        get { UserDefaults.standard.object(forKey: "autoUpdate") == nil ? true : UserDefaults.standard.bool(forKey: "autoUpdate") }
        set { UserDefaults.standard.set(newValue, forKey: "autoUpdate") }
    }

    /// "1.10.0" > "1.9.2". A leading "v" is ignored.
    static func newer(_ a: String, than b: String) -> Bool {
        func parts(_ s: String) -> [Int] { s.trimmingCharacters(in: CharacterSet(charactersIn: "vV")).split(separator: ".").map { Int($0) ?? 0 } }
        let x = parts(a), y = parts(b)
        for i in 0..<max(x.count, y.count) {
            let l = i < x.count ? x[i] : 0, r = i < y.count ? y[i] : 0
            if l != r { return l > r }
        }
        return false
    }

    static func verify(_ data: Data, signature: String, key: String = Updater.key) -> Bool {
        guard let k = Data(base64Encoded: key), let pub = try? Curve25519.Signing.PublicKey(rawRepresentation: k),
              let sig = Data(base64Encoded: signature.trimmingCharacters(in: .whitespacesAndNewlines)) else { return false }
        return pub.isValidSignature(sig, for: data)
    }

    /// Checks now, then every 6 hours.
    func start() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 8) { [weak self] in self?.check() }
        timer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.check() }
    }

    func check(manual: Bool = false) {
        if state == .checking || state == .installing { return }
        state = .checking
        guard let url = URL(string: Self.feed) else { state = .failed("Bad update feed"); return }
        var req = URLRequest(url: url, timeoutInterval: 20)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Wigglet/\(Self.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, resp, _ in
            DispatchQueue.main.async { self.handle(data, status: (resp as? HTTPURLResponse)?.statusCode ?? 0, manual: manual) }
        }.resume()
    }

    private func handle(_ data: Data?, status: Int, manual: Bool) {
        // 404 means nothing is published yet.
        guard status == 200, let data, let o = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let tag = o["tag_name"] as? String else { state = status == 404 ? .upToDate : .failed("Couldn't reach GitHub"); return }
        let assets = (o["assets"] as? [[String: Any]]) ?? []
        func asset(_ name: String) -> URL? {
            (assets.first { $0["name"] as? String == name }?["browser_download_url"] as? String).flatMap(URL.init(string:))
        }
        guard Self.newer(tag, than: Self.current) else { state = .upToDate; return }
        guard let z = asset("Wigglet.zip"), let s = asset("Wigglet.zip.sig") else { state = .upToDate; return }
        zipURL = z; sigURL = s
        notes = (o["body"] as? String) ?? ""
        let version = tag.trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
        state = .available(version)
        if Self.auto && !manual { install() }
    }

    func install() {
        guard case .available(let version) = state, let zipURL, let sigURL else { return }
        let target = URL(fileURLWithPath: Bundle.main.bundlePath)
        guard !target.path.contains("/AppTranslocation/"), FileManager.default.isWritableFile(atPath: target.deletingLastPathComponent().path) else {
            state = .failed("Move Wigglet to Applications to update"); return
        }
        state = .installing
        Task.detached {
            let result = await Self.download(zip: zipURL, sig: sigURL, version: version, into: target)
            await MainActor.run {
                switch result {
                case .success: self.relaunch(target)
                case .failure(let e): self.state = .failed(e.message)
                }
            }
        }
    }

    struct UpdateError: Error { let message: String }

    /// Download, verify the signature, unpack, check the bundle, then swap it in place.
    static func download(zip: URL, sig: URL, version: String, into target: URL) async -> Result<Void, UpdateError> {
        do {
            let (sigData, _) = try await URLSession.shared.data(from: sig)
            let (zipData, _) = try await URLSession.shared.data(from: zip)
            guard verify(zipData, signature: String(decoding: sigData, as: UTF8.self)) else {
                return .failure(UpdateError(message: "Update signature didn't match; not installed"))
            }
            let fm = FileManager.default
            let work = fm.temporaryDirectory.appendingPathComponent("wigglet-update-\(UUID().uuidString)")
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            defer { try? fm.removeItem(at: work) }
            let zipFile = work.appendingPathComponent("Wigglet.zip")
            try zipData.write(to: zipFile)
            let unzip = Process()
            unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzip.arguments = ["-x", "-k", zipFile.path, work.path]
            try unzip.run(); unzip.waitUntilExit()
            let app = work.appendingPathComponent(target.lastPathComponent)
            guard unzip.terminationStatus == 0, let info = Bundle(url: app)?.infoDictionary,
                  info["CFBundleIdentifier"] as? String == BUNDLE_ID,
                  info["CFBundleShortVersionString"] as? String == version else {
                return .failure(UpdateError(message: "Update package was not a \(PRODUCT_NAME) \(version) build"))
            }
            _ = try fm.replaceItemAt(target, withItemAt: app)
            return .success(())
        } catch {
            return .failure(UpdateError(message: "Update failed: \(error.localizedDescription)"))
        }
    }

    /// Waits for this process to exit, then opens the new copy. Paths go in as arguments, not script text.
    private func relaunch(_ app: URL) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "while kill -0 \"$1\" 2>/dev/null; do sleep 0.2; done; /usr/bin/open \"$0\"", app.path, String(getpid())]
        try? p.run()
        onInstalled()
        NSApp.terminate(nil)
    }

    var label: String {
        switch state {
        case .idle: return "Version \(Self.current)"
        case .checking: return "Checking for updates…"
        case .upToDate: return "Version \(Self.current) is the latest."
        case .available(let v): return "Version \(v) is available (you have \(Self.current))."
        case .installing: return "Installing the update…"
        case .failed(let m): return m
        }
    }

    /// Selftest: version order and signature checks, with a throwaway key.
    static func selfCheck() -> String? {
        if !newer("v1.1.0", than: "1.0.0") || newer("1.0.0", than: "1.0.0") || !newer("1.10", than: "1.9.2") || newer("1.0", than: "1.0.1") { return "version order" }
        let k = Curve25519.Signing.PrivateKey()
        let pub = k.publicKey.rawRepresentation.base64EncodedString()
        let data = Data("release".utf8)
        guard let sig = try? k.signature(for: data).base64EncodedString() else { return "sign" }
        if !verify(data, signature: sig, key: pub) { return "verify good" }
        if verify(Data("tampered".utf8), signature: sig, key: pub) { return "verify tampered" }
        if verify(data, signature: sig, key: Curve25519.Signing.PrivateKey().publicKey.rawRepresentation.base64EncodedString()) { return "verify wrong key" }
        if verify(data, signature: "not base64!", key: pub) { return "verify junk" }
        if Data(base64Encoded: publicKey)?.count != 32 { return "public key missing" }
        return nil
    }
}

/// Maintainer tools: `--gen-update-key` prints "private public" (base64), `--sign-update <file>` reads the private key on stdin
/// and prints the signature. The private key belongs in the Keychain (`app/package.sh` reads it from there).
func runUpdateKeyTool(_ args: [String]) -> Never {
    if args.contains("--gen-update-key") {
        let k = Curve25519.Signing.PrivateKey()
        print(k.rawRepresentation.base64EncodedString(), k.publicKey.rawRepresentation.base64EncodedString())
        exit(0)
    }
    guard let i = args.firstIndex(of: "--sign-update"), i + 1 < args.count,
          let data = FileManager.default.contents(atPath: args[i + 1]),
          let raw = Data(base64Encoded: String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)),
          let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw),
          let sig = try? key.signature(for: data) else {
        FileHandle.standardError.write(Data("usage: --sign-update <file> with the base64 private key on stdin\n".utf8)); exit(1)
    }
    print(sig.base64EncodedString())
    exit(0)
}
