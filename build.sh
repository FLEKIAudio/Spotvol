#!/bin/zsh
# Baut Spotvol.app neben diesem Skript.  Usage: zsh build.sh   or   zsh build.sh dmg
set -e
cd "$(dirname "$0")"
APP=Spotvol.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources" && cp Icon/Spotvol.icns "$APP/Contents/Resources/Spotvol.icns"
# Nur Apple Silicon (M1 und neuer)
swiftc -O -target arm64-apple-macos13.0 -o "$APP/Contents/MacOS/Spotvol" main.swift
codesign --force -s - -r '=designated => identifier "local.spotivol.app"' "$APP"
echo "Fertig: $(pwd)/$APP"

# Paket: Spotvol-<Version>.dmg mit App + Verknüpfung zu „Applications“
if [[ "$1" == "dmg" ]]; then
  VER=$(/usr/libexec/PlistBuddy -c "Print CFBundleShortVersionString" Info.plist)
  STAGE=$(mktemp -d)
  cp -R "$APP" "$STAGE/"
  ln -s /Applications "$STAGE/Applications"
  rm -f "Spotvol-$VER.dmg"
  hdiutil create -volname "Spotvol $VER" -srcfolder "$STAGE" -ov -format UDZO "Spotvol-$VER.dmg" >/dev/null
  rm -rf "$STAGE"
  echo "Paket: $(pwd)/Spotvol-$VER.dmg"
fi
