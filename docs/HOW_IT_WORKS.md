# How it works

Wigglet has two halves that share nothing but a folder: a hook that Claude Code runs, and the app that animates.

## 1. The hook

**Connect** adds one entry per event to `~/.claude/settings.json`. Each entry runs the app binary in hook mode:

```sh
[ -x '/Applications/Wigglet.app/Contents/MacOS/Wigglet' ] && '/Applications/Wigglet.app/Contents/MacOS/Wigglet' --hook; exit 0
```

The `exit 0` means a missing app never blocks Claude Code. Each entry has a 5-second timeout. Code: `HookInstaller` in [`app/Sources/Hooks.swift`](../app/Sources/Hooks.swift).

The hook is registered for these events:

`SessionStart` `SessionEnd` `UserPromptSubmit` `PreToolUse` `PostToolUse` `PostToolUseFailure` `Notification` `Stop` `StopFailure` `SubagentStart` `SubagentStop` `PreCompact` `PostCompact` `PermissionDenied`

`PreToolUse`, `PostToolUse` and `PostToolUseFailure` use the matcher `*`. Before saving, the installer removes any older Wigglet entries, so connecting twice never stacks duplicates. The first time it changes the file, it copies the original to `settings.json.wigglet-backup`.

## 2. One JSON file per session

`Wigglet --hook` reads the event from stdin and rewrites `~/.claude/wigglet/sessions/<session id>.json`. `SessionEnd` deletes that session's file.

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
| `activityId`, `subagentCount` | Finer activity for command-specific clips (deploy, git push, a test passing or failing, a sub-agent hand-off) and how many sub-agents are running |
| `hostBundleId`, `hostPid`, `hostApp`, `tty` | The app the session runs in and its terminal device, for Jump. Found once by walking the process tree with `sysctl` and `proc_pidpath` (no subprocesses); a hook call takes about 10 ms |

For `Bash`, the command text is only used to classify the activity (git, test, install, build). The file stores Claude's short description of the command, never the command itself.

## 3. Picking an animation

The app polls the folder. For each session, `AnimationCatalog.pick` in [`app/Sources/AnimationCatalog.swift`](../app/Sources/AnimationCatalog.swift) picks the clip with the highest priority whose condition holds:

| Priority | Examples |
|---|---|
| 60 | `ask`, `yourTurn`, `watch`, `flag` (waiting on you) |
| 50 | `oops`, `bandage` (three failures in a row) |
| 40 | `done`, `hello`, `tea` (a tool running for over 3 minutes), `drag`, `pet` |
| 30 | tool and command activities: `read`, `edit`, `deploy`, `push`… |
| 10–20 | ambient idles and `sleep` |

Team moves such as `highFive` and `parcel` look across sessions, for example two sessions finishing within 3 seconds of each other. Idle clips come from a weighted pool; each plays to its end, and the same one never plays twice in a row.

## 4. Frames

Every clip is a hand-authored list of integer cell poses with holds at 12 fps, in [`app/Sources/AnimationData.swift`](../app/Sources/AnimationData.swift). The data is separate from the drawing code. Props are drawn from the hand that holds them, so a hand and its prop always move together. When a character switches clips, connector frames move every pose field at most one cell per frame, so nothing pops.

Two audits keep it honest:

- `--pixel-audit`: every frame sits on the whole-cell grid (no rotation, scaling or anti-aliasing).
- `--frame-audit`: adjacent frames and loop seams change by at most N cells (20 by default, after the one-cell moves of lean and squash), held props touch a hand, and arms and legs stay connected to the body.

The full table, with triggers and timings, is in [ANIMATIONS.md](ANIMATIONS.md).

## 5. The team panel

Sessions come from two places: the hook files, and recently changed transcripts in `~/.claude/projects/` (so sessions that were open before you connected show up straight away; a hook file wins when both exist). Sessions untouched for longer than **Hide sessions untouched for** (default 3 hours) are left out. With **One Wigglet** on, a single character stands in for all of them: the one waiting on you, else the busiest, else the latest, and its hover card lists every session with its own Jump.

Sessions waiting on you are listed first. Up to six Wigglets are drawn side by side, and any more show as a `+N` badge. With two or more sessions, each Wigglet wears a scarf whose colour comes from its project name. The menu-bar icon shows the number of waiting sessions.

## 6. Hover card and Jump

The hover card reads the newest assistant message from the session's transcript: the last 64 KB, parsed from the end, skipping tool calls and sub-agent lines. A file watcher refreshes it at most 4 times a second while the card is open. The text is display-only (see [PRIVACY.md](PRIVACY.md)).

**Jump** uses what the hook recorded about where the session runs:

| Host | What Jump does | Tested on this build |
|---|---|---|
| Terminal | Selects the tab whose `tty` matches (AppleScript) | Yes: picked the right one of two tabs |
| iTerm2 | Selects the session whose `tty` matches (AppleScript) | Not tested |
| VS Code, Cursor, Windsurf | Opens the session's folder with that editor, which focuses its window | Not tested |
| Claude desktop app (Code tab) | Opens the session with `claude://resume?session=<id>&cwd=<path>`, the link Claude Code's own `/desktop` handoff uses | Not tested live (it would disturb a running session); link format covered by `--selftest` |
| Any other app | Brings the app forward with the same note | |
| App no longer running | Opens the session's folder in Finder | Yes |

## Cursor agents

Cursor has its own hooks (`~/.cursor/hooks.json`) with session, tool and stop events, a `conversation_id` and a `transcript_path`, so a connector that writes the same session files looks possible. It isn't built: it hasn't been checked against a real Cursor capture yet, and the event list differs between Cursor versions. Sessions from Cursor's agent don't appear in Wigglet today.
