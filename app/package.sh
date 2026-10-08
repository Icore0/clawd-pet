#!/bin/sh
# Zip and disk image for ClawdPet.app. Usage: ./package.sh
set -e
cd "$(dirname "$0")"
./build.sh
rm -f ClawdPet.zip ClawdPet.dmg
ditto -c -k --keepParent ClawdPet.app ClawdPet.zip
stage=$(mktemp -d)
cp -R ClawdPet.app "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Clawd Pet" -srcfolder "$stage" -ov -format UDZO ClawdPet.dmg
rm -rf "$stage"
echo "wrote $PWD/ClawdPet.zip and $PWD/ClawdPet.dmg"
