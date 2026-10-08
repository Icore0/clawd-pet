# Refreshing the repo after an app change

Every image and generated doc comes from the app's own code, so a refresh is five commands:

```sh
python3 docs/assets/build/render.py                                     # 1. images + docs/ANIMATIONS.md from app/Sources
cd app && ./build.sh && cd ..                                           # 2. build the app
HOME=/tmp/wigglet-test app/Wigglet.app/Contents/MacOS/Wigglet --selftest     # 3. checks (run from the repo root)
HOME=/tmp/wigglet-test app/Wigglet.app/Contents/MacOS/Wigglet --pixel-audit
git add -A docs README.md CHANGELOG.md && git commit -m "Refresh docs and assets"   # 5. review the diff first
```

Then update the counts in README.md and docs/REPO_SETUP.md if the number of clips crossed a round number. `docs/ANIMATIONS.md` states the exact count.

## Releasing v1.0.0 (only after the owner confirms the build is final)

```sh
cd app && ./package.sh && cd ..                       # Wigglet.zip + Wigglet.dmg
cd app && shasum -a 256 Wigglet.zip Wigglet.dmg > SHA256SUMS.txt && cd ..
# README: replace the "First release lands today" note with the download link; CHANGELOG: set the date
git tag v1.0.0 && git push origin main v1.0.0
gh release create v1.0.0 app/Wigglet.zip app/Wigglet.dmg app/SHA256SUMS.txt \
  --title "Wigglet 1.0.0" --notes-file docs/RELEASE_NOTES_1.0.0.md
```

## How the images are made

`docs/assets/build/export_frames.sh` compiles `ExportFrames.swift` together with `app/Sources/*.swift`, excluding `main.swift`. That gives a small tool that:

- exports looping cell frames for each scene in `docs/assets/build/scenes/` (`poses` mode): the app's own pose data, carried props, pixel effects and session scarves, with hops and shakes applied. These become the hero banner, the animated gallery, the team row and the social preview.
- renders the real hover card (`ActivityView`) offscreen for a demo session (`card` mode). Glass and buttons don't render offscreen, so it uses a solid panel.
- prints `AnimationCatalog.markdown()`, the same table as `--dump-catalog`.

`render.py` then composes dark and light variants with Pillow. Pixel art is drawn at whole-number scale only. Showcase clips loop in 12, 16 or 24 frames, so each 48-frame GIF loops with no seam. Nothing is written into `app/`.
