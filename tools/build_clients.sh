#!/usr/bin/env bash
# Exports the browser (PWA) build to build/web and a debug-signed APK to build/download/tinker.apk.
# server/deploy.sh calls this first so the image always ships the game matching its server code.
set -euo pipefail
cd "$(dirname "$0")/.."
godot --headless --path game --import >/dev/null 2>&1 || true
rm -rf build/web build/download && mkdir -p build/web build/download
godot --headless --path game --export-release Web ../build/web/index.html >/dev/null 2>&1
test -s build/web/index.wasm && test -s build/web/index.pck
if [ ! -f build/debug.keystore ]; then
  keytool -genkeypair -keystore build/debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$PWD/build/debug.keystore GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey \
GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android godot --headless --path game --export-debug Android ../build/download/tinker.apk >/dev/null 2>&1
rm -f build/download/*.idsig
test -s build/download/tinker.apk
echo "clients: web $(du -sh build/web | cut -f1), apk $(du -sh build/download/tinker.apk | cut -f1)"
