#!/bin/sh
# Zip and disk image for Wigglet.app. Usage: ./package.sh
set -e
cd "$(dirname "$0")"
./build.sh
rm -f Wigglet.zip Wigglet.dmg
ditto -c -k --keepParent Wigglet.app Wigglet.zip
stage=$(mktemp -d)
cp -R Wigglet.app "$stage/"
ln -s /Applications "$stage/Applications"
hdiutil create -volname "Wigglet" -srcfolder "$stage" -ov -format UDZO Wigglet.dmg
rm -rf "$stage"
echo "wrote $PWD/Wigglet.zip and $PWD/Wigglet.dmg"
