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
# Updates install only if this signature verifies against the public key in Updater.swift.
# The private key stays in the login Keychain (item "wigglet-release-key").
security find-generic-password -s wigglet-release-key -a ed25519 -w | Wigglet.app/Contents/MacOS/Wigglet --sign-update Wigglet.zip > Wigglet.zip.sig
shasum -a 256 Wigglet.zip Wigglet.dmg > SHA256SUMS.txt
echo "wrote $PWD/Wigglet.zip, Wigglet.zip.sig, Wigglet.dmg and SHA256SUMS.txt (version $(cat VERSION))"
