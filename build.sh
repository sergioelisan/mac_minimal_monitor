#!/bin/zsh
# Compila e monta "Resources Monitor.app" na pasta atual.
set -e
cd "$(dirname "$0")"
swift build -c release
APP="Resources Monitor.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp .build/release/ResourcesMonitor "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --force --sign - "$APP" >/dev/null 2>&1 || true
echo "OK: $(pwd)/$APP"
echo "Para abrir: open \"$(pwd)/$APP\""
echo "Para instalar: cp -R \"$APP\" /Applications/ && open \"/Applications/$APP\""
