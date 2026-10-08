# Security

Please report vulnerabilities privately through GitHub: **Security → Report a vulnerability** on this repository. Don't open a public issue for security problems.

Include the version, macOS version, steps to reproduce, and what an attacker could do. You'll get a reply as soon as the maintainer can look at it.

Areas that matter most:

- the hook installer, which edits `~/.claude/settings.json`
- `Wigglet --hook`, which parses JSON from Claude Code on stdin
- API key handling in the Keychain (one item per provider)
- the chat's `claude -p` call, which must never pass user text through a shell
- transcript discovery, which reads the end of `~/.claude/projects/*/*.jsonl`

## What's already in place

- Hooks only write metadata, to files named by a validated session id.
- The hook command quotes the app path for `sh`; AppleScript only ever sees a terminal device name that matches `/dev/ttysNNN`.
- Chat runs `claude` with an argument array (no shell), no tools and no MCP servers.
- API endpoints are fixed. A test override only works when `HOME` is a temporary folder.
- CI actions are pinned to commit SHAs, the workflow token is read-only, and only GitHub-owned actions may run.
