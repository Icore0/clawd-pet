# Refreshing the repo after an app change

Every image and generated doc comes from the app's own code, so a refresh is five commands:

```sh
python3 docs/assets/build/render.py                                     # 1. images + docs/ANIMATIONS.md from app/Sources
cd app && ./build.sh && cd ..                                           # 2. build the app
HOME=/tmp/clawd-test app/ClawdPet.app/Contents/MacOS/ClawdPet --selftest     # 3. checks (run from the repo root)
HOME=/tmp/clawd-test app/ClawdPet.app/Contents/MacOS/ClawdPet --pixel-audit
git add -A docs README.md CHANGELOG.md && git commit -m "Refresh docs and assets"   # 5. review the diff first
```

Then update the counts in README.md and docs/REPO_SETUP.md if the number of clips crossed a round number. `docs/ANIMATIONS.md` states the exact count.

## Releasing v1.0.0 (only after the owner confirms the build is final)

```sh
cd app && ./package.sh && cd ..                       # ClawdPet.zip + ClawdPet.dmg
cd app && shasum -a 256 ClawdPet.zip ClawdPet.dmg > SHA256SUMS.txt && cd ..
# README: replace the "First release lands today" note with the download link; CHANGELOG: set the date
git tag v1.0.0 && git push origin main v1.0.0
gh release create v1.0.0 app/ClawdPet.zip app/ClawdPet.dmg app/SHA256SUMS.txt \
  --title "Clawd Pet 1.0.0" --notes-file docs/RELEASE_NOTES_1.0.0.md
```

## How the images are made

`docs/assets/build/export_frames.sh` compiles `ExportFrames.swift` together with `app/Sources/*.swift`, excluding `main.swift`. That gives a small tool that:

- dumps every catalog clip as 12 fps cells, using the app's recording `Pen`. These become the gallery.
- renders the real team panel (`Renderer.drawTeam`) offscreen for the scenes in `docs/assets/build/scenes/`. These become the hero GIF, the team shot and the social preview.
- prints `AnimationCatalog.markdown()`, the same table as `--dump-catalog`.

`render.py` then composes the dark and light variants with Pillow. Pixel art is only scaled by whole numbers. Nothing is written into `app/`.
