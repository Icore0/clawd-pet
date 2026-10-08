# Contributing

Thanks for helping. Small, focused pull requests are easiest to review.

## Build and check

```sh
cd app && ./build.sh                                                    # universal Wigglet.app
cd .. && HOME=/tmp/wigglet-test app/Wigglet.app/Contents/MacOS/Wigglet --selftest     # run from the repo root
HOME=/tmp/wigglet-test app/Wigglet.app/Contents/MacOS/Wigglet --pixel-audit           # every clip on the cell grid
HOME=/tmp/wigglet-test app/Wigglet.app/Contents/MacOS/Wigglet --frame-audit           # no pops, seams, floating props or loose limbs
```

Always use a throwaway `HOME` under `/tmp/` for test flags, so nothing touches your real `~/.claude`. `--selftest` refuses to run with any other `HOME`.

Useful flags: `--gallery` plays every clip, `--demo-team N` writes N fake sessions, and `--dump-catalog` prints the animation table.

## Proposing an animation

1. Open a **feature request** with the trigger (which hook event, tool or command) and a rough storyboard.
2. Add the clip to `AnimationCatalog.all` with an honest `status`: `needs-verify` until a recorded payload in `fixtures/` exercises it.
3. Author its frames in `app/Sources/AnimationData.swift` (integer cell poses with holds). Props go in `drawProp`, drawn from a hand.
4. Run `--pixel-audit` and `--frame-audit`, then `python3 docs/assets/build/render.py` to regenerate `docs/ANIMATIONS.md` and the images.

## Pixel rules

- Whole cells only: integer positions and sizes, no rotation, no scaling, no anti-aliasing.
- Don't change Wigglet's silhouette, proportions or colours (`#D97757` body, `#BE684B` shade). New work goes into poses, props, effects and timing.
- Props use their own palette, so they never blend into the orange body.

## Commits

Describe what changed and why. Never commit secrets, `.env` files or paths from your own machine.
