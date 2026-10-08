# Changelog

All notable changes are listed here. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [Unreleased]

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
