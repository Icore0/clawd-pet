# Privacy

Wigglet has no accounts, analytics, telemetry or update checks.

## On your disk

| Where | What |
|---|---|
| `~/.claude/wigglet/sessions/<id>.json` | One file per running session: the project name, its working folder, the transcript path, tool names, file base names, short labels (a search pattern cut to about 30 characters, a web host name, Claude's description of a command), line counts and timings, and where the session runs (the host app's bundle id, process id and path, and the terminal device such as `/dev/ttys003`) so Jump can find it. Deleted when the session ends. |
| `~/.claude/settings.json` | The hook entries that Connect adds. Your original file is copied to `settings.json.wigglet-backup` the first time. |
| macOS Keychain (`dev.wigglet.app` / `anthropic`, `openai`, `openrouter`, `gemini`) | Your API keys, if you add any. This Mac only; not synced. |
| `defaults` (`dev.wigglet.app`) | Preferences: size, position, sounds, chat provider and model ids, one-Wigglet mode, how long idle sessions stay, whether the hover card shows the latest message. |

**Never stored:** file contents, full shell commands, prompts or replies from your Claude Code sessions.

## Shown, not stored

While a hover card is open, the app reads the end of that session's transcript (at most the last 64 KB) to show the newest assistant message and your last prompt. That text is only displayed. It is never copied into the session file, a log, or any network request. Turn it off with **Show latest message in hover card** in the menu (it's on by default).

## Finding sessions

To show sessions that were open before Wigglet connected, the app lists `~/.claude/projects/*/*.jsonl` and, for files changed recently, reads the end of each (at most 64 KB) for three fields: the working folder, the session title and which app it runs in. Nothing else from the transcript is kept, and headless `claude -p` runs are skipped.

## Jump to session

Jump uses AppleScript only for Terminal and iTerm2, to select the tab whose terminal device matches the session. macOS asks once whether Wigglet may control that app. For other apps it only brings the app forward, or opens the session's folder in Finder if the app has quit.

## Over the network

The only network request the app makes is for chat:

- **Claude Code (default):** chat runs your local `claude -p`, which talks to Anthropic under your own Claude Code login. It runs with no tools and no MCP servers.
- **Anthropic, OpenAI, OpenRouter or Gemini:** your chat messages (the last 20 lines) go to that provider's API (`api.anthropic.com`, `api.openai.com`, `openrouter.ai`, `generativelanguage.googleapis.com`) with your key.
- **Ollama:** messages go to `localhost:11434` and stay on your Mac.
- In every case, when you open chat from a Wigglet, a short summary of that session is added: project, folder, current activity, recent action labels and counters.
- **Transcript text** is never included, unless you turn on the hidden setting `defaults write dev.wigglet.app transcriptTail -bool true`. Then the last 20 lines of that session's transcript are added to the summary.

Updates: every six hours the app asks `api.github.com` for this repository's latest release, and downloads it from GitHub if it's newer. The request carries only the app's version in its User-Agent.

Apart from update checks, if you never open chat, the app makes no network requests.
