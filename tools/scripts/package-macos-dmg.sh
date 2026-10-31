#!/usr/bin/env bash
set -euo pipefail

version="${1:?Usage: package-macos-dmg.sh <version> <arch>}"
arch="${2:?Usage: package-macos-dmg.sh <version> <arch>}"

app="apps/pi_frame/build/macos/Build/Products/Release/pi_frame.app"
mkdir -p "$app/Contents/MacOS" "$app/Contents/Resources" dist/dmg

cp apps/agentd/dist/pi-agentd.cjs "$app/Contents/MacOS/pi-agentd.cjs"
node_bin="$(command -v node)"
cp "$node_bin" "$app/Contents/MacOS/node"
cp "$(dirname "$(dirname "$node_bin")")/LICENSE" "$app/Contents/Resources/NODE-LICENSE.txt"
chmod +x "$app/Contents/MacOS/node"

rm -rf "$app/Contents/MacOS/web"
cp -R apps/pi_frame/build/web "$app/Contents/MacOS/web"
test -s "$app/Contents/MacOS/web/index.html"

cp -R "$app" dist/dmg/PiFrame.app
codesign --force --deep --sign - dist/dmg/PiFrame.app
ln -s /Applications dist/dmg/Applications

cp "packaging/macos/LEGGIMI - Come aprire l'app.txt" dist/dmg/
cp "packaging/macos/README - How to open.txt" dist/dmg/

test -x "$app/Contents/MacOS/pi_frame"
test -x "$app/Contents/MacOS/node"
test -s "$app/Contents/MacOS/pi-agentd.cjs"
test -s "$app/Contents/MacOS/web/index.html"
test -s "$app/Contents/Resources/NODE-LICENSE.txt"
test -s "dist/dmg/LEGGIMI - Come aprire l'app.txt"
test -s "dist/dmg/README - How to open.txt"

hdiutil create -volname 'PiFrame' -srcfolder dist/dmg -ov -format UDZO "dist/PiFrame-${version}-macos-${arch}.dmg"
rm -rf dist/dmg
echo "Successfully created dist/PiFrame-${version}-macos-${arch}.dmg"

