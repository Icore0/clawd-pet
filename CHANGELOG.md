# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

### Added
- Updates: Wigglet checks GitHub Releases every six hours and installs a new version only once it's published and its Ed25519 signature checks out. **Install updates automatically** (on by default) and **Check now** are in Settings; **Check for Updates…** is in the menu.
- Finds sessions that were already open: recent transcripts in `~/.claude/projects/` show up without waiting for a hook. Setup step 3 completes as soon as one is found.
- **Hide sessions untouched for** 30m / 1h / 3h / 8h / 1d (default 3h). The Sessions list is sorted by most recent and shows when each was last active.
- **One Wigglet** mode: one character for every session, with a hover card that lists them all.
- Chat providers: Claude Code (default, no key), Anthropic, OpenAI, OpenRouter, Gemini and Ollama, each with its own Keychain item and an editable model id.
- A new chat bar: provider chip with a menu, the session it's about, the conversation so far, multi-line input and key hints.

### Security
- Chat runs `claude` with an argument array instead of a shell string, with no tools and no MCP servers.
- Session ids are validated before they become file names; terminal device names are validated before AppleScript; the hook command quotes the app path.
- Wigglet's own chat no longer shows up as a session.
- CI actions pinned to commit SHAs; Dependabot for GitHub Actions; CODEOWNERS.

### Changed
- Renamed to **Wigglet** (app, bundle id `dev.wigglet.app`, state folder `~/.claude/wigglet/`). Connecting replaces hooks left by the earlier Clawd Pet builds.
- Wigglet is now a full app with a Dock icon and a main window: Home (setup with live checks), Sessions (with Jump), Animations (browse and play every clip), Settings and About.
- Setup no longer uses a pop-up alert. It warns when the app runs from a temporary location (App Translocation) where hooks would break, and waits until your first session appears.
- New app icon: the pixel mascot on a transparent background.
- The app's UI follows the website's design system: ink background, square corners, hairline rows, mono labels, one clay accent. The hover card, toast and chat bar use the same square panels.
- Claude desktop app: sessions in its Code tab show their host, and Jump opens them with `claude://resume` (the link Claude Code's `/desktop` uses).

### Added
- Hand-authored 12 fps frame data for every clip (`AnimationData.swift`), connector frames between clips, a profile turn, a crouched typing stance, and dithered pop-in and fade-out for session start and end.
- New clips: `testPass`, `testFail`, `handoff` (sub-agent starts), `grind` (long turns).
- `--frame-audit`: fails on pops, loop seams, props that leave the hand, and detached limbs.
- Live hover card: stays open while you move onto it, shows the session's latest message (read locally, display only; menu toggle), Return or ⌘J jumps, Esc closes.
- Jump to session: exact tab in Terminal (tested) and iTerm2, the folder's window in VS Code-family editors, otherwise the app comes forward with a note.

### Fixed
- Idle clips no longer flip between two animations on every frame.
- Squash and crouch keep the feet on the ground.
- Hats follow the body when it leans.
- Effects are drawn on the pixel grid instead of as smooth text and ellipses.

### Removed
- `alarm`: its trigger couldn't be verified.

## [1.0.0] - not yet released

### Added
- One Wigglet per Claude Code session, up to six side by side, plus a `+N` badge. Waiting sessions move to the front.
- Hooks for 14 Claude Code events that write one JSON file per session to `~/.claude/wigglet/sessions/`.
- An animation catalog with priorities, triggers and 12 fps whole-cell clips. See `docs/ANIMATIONS.md`.
- Team moves between sessions: high-five, pass-the-parcel, glances and bumps.
- A hover card with project, turn timer, tool count and recent actions.
- Chat bar (<kbd>⌃⌥Space</kbd>) on your own OpenRouter key stored in the Keychain, with the local `claude` CLI as an alternative.
- Menu-bar icon with a count of waiting sessions, plus Connect and Disconnect.
- `--selftest`, `--pixel-audit`, `--gallery` and `--dump-catalog`.
