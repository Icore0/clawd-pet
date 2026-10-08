# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
- One Clawd per Claude Code session, up to six side by side, plus a `+N` badge. Waiting sessions move to the front.
- Hooks for 14 Claude Code events that write one JSON file per session to `~/.claude/clawd/sessions/`.
- An animation catalog with priorities, triggers and 12 fps whole-cell clips. See `docs/ANIMATIONS.md`.
- Team moves between sessions: high-five, pass-the-parcel, glances and bumps.
- A hover card with project, turn timer, tool count and recent actions.
- Chat bar (<kbd>⌃⌥Space</kbd>) on your own OpenRouter key stored in the Keychain, with the local `claude` CLI as an alternative.
- Menu-bar icon with a count of waiting sessions, plus Connect and Disconnect.
- `--selftest`, `--pixel-audit`, `--gallery` and `--dump-catalog`.
