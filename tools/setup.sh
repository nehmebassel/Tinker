#!/usr/bin/env bash
# One-shot local toolchain for Tinker on Linux x86_64. Idempotent. Run from the repo root.
#   bash tools/setup.sh
# Installs: Godot 4.5.1 (CLI), export templates, Android cmdline-tools + platform-tools/build-tools 35/platform 35,
# writes Godot editor settings for the SDK/JDK, generates a debug keystore in build/.
# Requires: curl, unzip, Java 17 or 21 (JAVA_HOME or /usr/lib/jvm/*).
set -euo pipefail
V=${GODOT_VERSION:-4.5.1-stable}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOOLS=$ROOT/tools
SDK=${ANDROID_HOME:-$TOOLS/android-sdk}
mkdir -p "$TOOLS" "$ROOT/build"

if ! command -v godot >/dev/null || ! godot --version | grep -q "${V%%-*}"; then
  echo "== Godot $V"
  curl -sSL -o "$TOOLS/godot.zip" "https://github.com/godotengine/godot/releases/download/$V/Godot_v${V}_linux.x86_64.zip"
  unzip -oq "$TOOLS/godot.zip" -d "$TOOLS" && rm "$TOOLS/godot.zip"
  chmod +x "$TOOLS/Godot_v${V}_linux.x86_64"
  sudo ln -sf "$TOOLS/Godot_v${V}_linux.x86_64" /usr/local/bin/godot 2>/dev/null || ln -sf "$TOOLS/Godot_v${V}_linux.x86_64" "$HOME/.local/bin/godot"
fi
godot --version

TPL=$HOME/.local/share/godot/export_templates/${V/-stable/.stable}
if [ ! -f "$TPL/android_debug.apk" ]; then
  echo "== export templates"
  curl -sSL -o "$TOOLS/tpz.zip" "https://github.com/godotengine/godot/releases/download/$V/Godot_v${V}_export_templates.tpz"
  mkdir -p "$(dirname "$TPL")" && unzip -oq "$TOOLS/tpz.zip" -d "$TOOLS/tpz" && mv "$TOOLS/tpz/templates" "$TPL" && rm -rf "$TOOLS/tpz" "$TOOLS/tpz.zip"
fi

if [ ! -x "$SDK/cmdline-tools/latest/bin/sdkmanager" ]; then
  echo "== Android cmdline-tools"
  curl -sSL -o "$TOOLS/ct.zip" https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
  mkdir -p "$SDK/cmdline-tools" && unzip -oq "$TOOLS/ct.zip" -d "$SDK/cmdline-tools" && mv "$SDK/cmdline-tools/cmdline-tools" "$SDK/cmdline-tools/latest" && rm "$TOOLS/ct.zip"
fi
export PATH=$SDK/cmdline-tools/latest/bin:$PATH
yes | sdkmanager --licenses >/dev/null 2>&1 || true
sdkmanager "platform-tools" "build-tools;36.0.0" "platforms;android-36" >/dev/null

JDK=${JAVA_HOME:-$(ls -d /usr/lib/jvm/java-*-openjdk-amd64 2>/dev/null | sort | tail -1)}
mkdir -p "$HOME/.config/godot"
cat > "$HOME/.config/godot/editor_settings-4.5.tres" <<EOT
[gd_resource type="EditorSettings" format=3]

[resource]
export/android/android_sdk_path = "$SDK"
export/android/java_sdk_path = "$JDK"
EOT

if [ ! -f "$ROOT/build/debug.keystore" ]; then
  keytool -genkeypair -keystore "$ROOT/build/debug.keystore" -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
echo
echo "Done. Export a debug APK with:"
echo "  export GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$ROOT/build/debug.keystore GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android"
echo "  godot --headless --path game --import && godot --headless --path game --export-debug Android ../build/tinker-debug.apk"
