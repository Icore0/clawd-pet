# Security

Please report vulnerabilities privately through GitHub: **Security → Report a vulnerability** on this repository. Don't open a public issue for security problems.

Include the version, macOS version, steps to reproduce, and what an attacker could do. You'll get a reply as soon as the maintainer can look at it.

Areas that matter most:

- the hook installer, which edits `~/.claude/settings.json`
- `ClawdPet --hook`, which parses JSON from Claude Code on stdin
- OpenRouter key handling in the Keychain
