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

## Releasing (only after the owner confirms the build is final)

Users stay on the version they have until a release is **published** on GitHub. Building, committing and pushing never reaches them. Drafts and pre-releases don't either (the app reads `releases/latest`).

```sh
V=1.1.0
echo $V > app/VERSION                                  # 1. bump the version
cd app && ./package.sh && cd ..                        # 2. Wigglet.zip, Wigglet.zip.sig, Wigglet.dmg, SHA256SUMS.txt
# 3. CHANGELOG: move Unreleased under [$V] with today's date; write docs/RELEASE_NOTES_$V.md
git commit -am "Release $V" && git tag v$V && git push origin main v$V
gh release create v$V app/Wigglet.zip app/Wigglet.zip.sig app/Wigglet.dmg app/SHA256SUMS.txt \
  --title "Wigglet $V" --notes-file docs/RELEASE_NOTES_$V.md   # 4. this is the moment everyone gets it
```

Within six hours every running copy sees the release, checks `Wigglet.zip.sig` against the public key built into the app, and installs it (or shows **Update now** if the user turned automatic updates off).

**The signing key.** `package.sh` signs with the Ed25519 private key in the login Keychain, item `wigglet-release-key`. It never goes in the repo. Back it up somewhere safe (a password manager):

```sh
security find-generic-password -s wigglet-release-key -a ed25519 -w    # prints the private key; store it, don't paste it anywhere public
```

If it's lost, installed copies can't verify new releases and users would have to download the next version by hand. To restore it on another Mac: `security add-generic-password -s wigglet-release-key -a ed25519 -w '<key>'`.

## How the images are made

`docs/assets/build/export_frames.sh` compiles `ExportFrames.swift` together with `app/Sources/*.swift`, excluding `main.swift`. That gives a small tool that:

- exports looping cell frames for each scene in `docs/assets/build/scenes/` (`poses` mode): the app's own pose data, carried props, pixel effects and session scarves, with hops and shakes applied. These become the hero banner, the animated gallery, the team row and the social preview.
- renders the real hover card (`ActivityView`) offscreen for a demo session (`card` mode). Glass and buttons don't render offscreen, so it uses a solid panel.
- prints `AnimationCatalog.markdown()`, the same table as `--dump-catalog`.

`render.py` then composes dark and light variants with Pillow. Pixel art is drawn at whole-number scale only. Showcase clips loop in 12, 16 or 24 frames, so each 48-frame GIF loops with no seam. Nothing is written into `app/`.
