## What and why

## Checks
- [ ] `cd app && ./build.sh` succeeds
- [ ] `--selftest` and `--pixel-audit` pass, run from the repo root with a throwaway `HOME`
- [ ] If clips changed: ran `python3 docs/assets/build/render.py` and committed the regenerated docs and images
- [ ] No secrets, `.env` files or personal paths
