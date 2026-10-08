#!/bin/sh
# Notarize Wigglet.dmg when NOTARY_PROFILE is set. Usage: ./notarize.sh
cd "$(dirname "$0")"
if [ -z "$NOTARY_PROFILE" ]; then
  echo "skipping, no Apple credentials"
  exit 0
fi
xcrun notarytool submit Wigglet.dmg --keychain-profile "$NOTARY_PROFILE" --wait
