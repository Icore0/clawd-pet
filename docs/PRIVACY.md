# Privacy

Clawd Pet has no accounts, analytics, telemetry or update checks.

## On your disk

| Where | What |
|---|---|
| `~/.claude/clawd/sessions/<id>.json` | One file per running session: the project name, its working folder, the transcript path, tool names, file base names, short labels (a search pattern cut to about 30 characters, a web host name, Claude's description of a command), line counts and timings. Deleted when the session ends. |
| `~/.claude/settings.json` | The hook entries that Connect adds. Your original file is copied to `settings.json.clawd-backup` the first time. |
| macOS Keychain (`dev.clawdpet.app` / `openrouter`) | Your OpenRouter key, if you add one. |
| `defaults` (`dev.clawdpet.app`) | Preferences: size, position, sounds, chat model. |

**Never stored:** file contents, full shell commands, prompts or replies from your Claude Code sessions.

## Over the network

The only network request the app makes is for chat:

- **With an OpenRouter key:** your chat messages (the last 20 lines) go to `openrouter.ai`. When you open chat from a Clawd, a short summary of that session is added: project, folder, current activity, recent action labels and counters.
- **Without a key, or with "Use Claude Code CLI instead":** chat runs your local `claude -p`, which talks to Anthropic under your own Claude Code login.
- **Transcript text** is never included, unless you turn on the hidden setting `defaults write dev.clawdpet.app transcriptTail -bool true`. Then the last 20 lines of that session's transcript are added to the summary.

If you never open chat, the app makes no network requests.
