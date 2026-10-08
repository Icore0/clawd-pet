# Clawd Pet

A small floating companion for [Claude Code](https://claude.com/product/claude-code) on macOS. One Clawd per running session, each reacting live to what that session is doing, with 60+ animations and a glass chat bar that runs on your own OpenRouter key.

Unofficial fan project. Not affiliated with or endorsed by Anthropic. "Claude" and the mascot belong to Anthropic.

## What it does

- **One Clawd per session.** Run three Claude Code sessions, get three Clawds in a row, each with a name tag and its own accent scarf. A session that needs your OK steps to the front. More than six shows a "+N" badge.
- **Real activity, not a spinner.** Reading, editing, running commands, searching, browsing the web, spawning sub-agents, planning, testing, building, git, installing: each has its own animation, prop and wind-up. Deploys launch a rocket, a push sends a paper plane, a long-running command earns a tea break, three failures in a row earns a bandage.
- **Hover** a Clawd for its activity card: project, turn timer, tool count, last actions.
- **Team behaviours.** Two sessions finish together: high-five. One finishes while others work: it passes a parcel and naps. Two sessions editing the same file: they glance at each other.
- **Play with it.** Drag, throw, pet, poke, double-click to spin, shake it dizzy.
- **Chat bar** (click a Clawd or press ⌃⌥Space): ask anything, or about that specific session. Answers stream from OpenRouter using your own key, so it never touches your Claude Code usage.

## Install

1. Download `ClawdPet.dmg` from Releases and drag **Clawd Pet** to Applications.
2. First launch: right-click the app, choose **Open** (it is not notarized yet), or run `xattr -dr com.apple.quarantine /Applications/ClawdPet.app`.
3. Click **Connect**. This adds a few hook entries to `~/.claude/settings.json` (a backup is saved next to it). Disconnect any time from the menu-bar icon.

Requires macOS 13 or later. Liquid Glass on macOS 26+, frosted glass before.

## Chat setup

Menu-bar icon, then **AI settings**. Paste an [OpenRouter](https://openrouter.ai) API key and pick a model. The key is stored in the macOS Keychain, never in a file. Chat is plain Q&A (no tools). If you prefer, switch back to the Claude Code CLI there.

## Privacy

- Hooks write one small JSON file per session to `~/.claude/clawd/sessions/`: tool names, file base-names, command descriptions, counters. Never file contents or full commands.
- The app makes **no network requests** except chat, and only after you add an OpenRouter key. A chat request contains your typed message, your recent chat messages, and, only if you turn it on, a summary of the session you are asking about. Nothing is sent otherwise. No analytics, no accounts.

## How it works

Claude Code hooks call `ClawdPet --hook`, which updates that session's file. The app watches the folder and animates. Headless: `ClawdPet.app/Contents/MacOS/ClawdPet --install-hooks` / `--remove-hooks`.

## Build

```sh
cd app && ./build.sh     # universal ClawdPet.app, needs Xcode command line tools
./package.sh             # zip + dmg
```

Test flags (use a temp HOME, never your real one): `--selftest`, `--demo-team N`, `--gallery`, `--dump-catalog`.

## License

TODO (owner to decide before public release).
