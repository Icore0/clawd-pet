# Repo setup

Values used for the GitHub repository settings. `gh` commands that apply them are at the bottom.

**About:** A floating pixel companion for Claude Code on macOS: one Wigglet per session, 80+ animations. Unofficial fan project.

**Website:** _(empty until the landing page has a domain)_

**Topics:** `macos` `swift` `claude-code` `desktop-pet` `pixel-art` `menu-bar` `ai-tools` `openrouter` `developer-tools` `mascot`

**Features:** Issues on, Wiki off, Projects off, Discussions off. Private vulnerability reporting on.

**Social preview:** Settings → General → Social preview → upload `docs/assets/social-preview.png` (1280×640). GitHub has no API for this step.

```sh
gh repo edit Icore0/wigglet \
  --description "A floating pixel companion for Claude Code on macOS: one Wigglet per session, 80+ animations. Unofficial fan project." \
  --enable-issues --enable-wiki=false --enable-projects=false --enable-discussions=false \
  --add-topic macos,swift,claude-code,desktop-pet,pixel-art,menu-bar,ai-tools,openrouter,developer-tools,mascot
gh api -X PUT repos/Icore0/wigglet/private-vulnerability-reporting
```
