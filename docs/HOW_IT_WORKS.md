# How it works

Clawd Pet has two halves that share nothing but a folder: a hook that Claude Code runs, and the app that animates.

## 1. The hook

**Connect** adds one entry per event to `~/.claude/settings.json`. Each entry runs the app binary in hook mode:

```sh
[ -x '/Applications/ClawdPet.app/Contents/MacOS/ClawdPet' ] && '/Applications/ClawdPet.app/Contents/MacOS/ClawdPet' --hook; exit 0
```

The `exit 0` means a missing app never blocks Claude Code. Each entry has a 5-second timeout. Code: `HookInstaller` in [`app/Sources/Hooks.swift`](../app/Sources/Hooks.swift).

The hook is registered for these events:

`SessionStart` `SessionEnd` `UserPromptSubmit` `PreToolUse` `PostToolUse` `PostToolUseFailure` `Notification` `Stop` `StopFailure` `SubagentStart` `SubagentStop` `PreCompact` `PostCompact` `PermissionDenied`

`PreToolUse`, `PostToolUse` and `PostToolUseFailure` use the matcher `*`. Before saving, the installer removes any older Clawd Pet entries, so connecting twice never stacks duplicates. The first time it changes the file, it copies the original to `settings.json.clawd-backup`.

## 2. One JSON file per session

`ClawdPet --hook` reads the event from stdin and rewrites `~/.claude/clawd/sessions/<session id>.json`. `SessionEnd` deletes that session's file.

| Field | What it holds |
|---|---|
| `sid`, `project`, `cwd` | Session id, folder name, and the session's working folder |
| `transcript` | Path of the Claude Code transcript (the path only, not the contents) |
| `startedAt`, `ts`, `turnStart` | Timestamps in ms |
| `mood` | `hello`, `working`, `waiting`, `done`, `oops` or `bye` |
| `kind` | `read`, `edit`, `bash`, `search`, `web`, `agent`, `plan`, `compact`, `test`, `build`, `git`, `install`, `ask`… |
| `say`, `delta` | A short label: a file base name, a truncated search pattern, a host name, or the command's description. `delta` is a line count like `+12 −3` |
| `lastTool`, `toolCount`, `toolStartedAt`, `toolTimes`, `lastDurationMs` | Tool counters and timings |
| `errorStreak`, `lastErrorAt` | Consecutive failed tool calls. A failure that is an interrupt is not counted |
| `activityId`, `subagentCount` | Finer activity for command-specific clips, such as deploy or git push, and how many sub-agents are running |

For `Bash`, the command text is only used to classify the activity (git, test, install, build). The file stores Claude's short description of the command, never the command itself.

## 3. Picking an animation

The app polls the folder. For each session, `AnimationCatalog.pick` in [`app/Sources/AnimationCatalog.swift`](../app/Sources/AnimationCatalog.swift) picks the clip with the highest priority whose condition holds:

| Priority | Examples |
|---|---|
| 70 | `alarm` |
| 60 | `ask`, `yourTurn`, `watch`, `flag` (waiting on you) |
| 50 | `oops`, `bandage` (three failures in a row) |
| 40 | `done`, `hello`, `tea` (a tool running for over 3 minutes), `drag`, `pet` |
| 30 | tool and command activities: `read`, `edit`, `deploy`, `push`… |
| 10–20 | ambient idles and `sleep` |

Team moves such as `highFive` and `parcel` look across sessions, for example two sessions finishing within 3 seconds of each other. Idle clips come from a weighted pool and don't repeat within 20 seconds. Every clip is drawn on a whole-cell grid at 12 fps, and `--pixel-audit` checks that for each one.

The full table, with triggers and timings, is in [ANIMATIONS.md](ANIMATIONS.md).

## 4. The team panel

Sessions waiting on you are listed first. Up to six Clawds are drawn side by side, and any more show as a `+N` badge. With two or more sessions, each Clawd wears a scarf whose colour comes from its project name. The menu-bar icon shows the number of waiting sessions.
