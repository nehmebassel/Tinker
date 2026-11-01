#!/usr/bin/env bash
# Builds the player-facing clients into build/:
#   build/web/                 browser (PWA) build, served by the backend at /play/
#   build/download/tinker.apk  Android build with the TinkerPush (FCM) plugin, served at /download/
# Needs: Godot + export templates, Android SDK (ANDROID_HOME), JDK, and either gcloud access to the
# Firebase project (PROJECT, ANDROID_APP_ID) or an existing build/firebase/google-services.json.
# FIREBASE_DUMMY=1 builds with placeholder Firebase values (CI: proves it builds; push won't work).
set -euo pipefail
cd "$(dirname "$0")/.."
export ANDROID_HOME=${ANDROID_HOME:-$HOME/tools/android-sdk}
[ -d "$ANDROID_HOME" ] || export ANDROID_HOME=/home/claude/tools/android-sdk
GRADLE=${GRADLE:-$(command -v gradle || echo /opt/gradle-8.14.3/bin/gradle)}
mkdir -p build/firebase

# 1. Firebase Android config (never committed)
GS=build/firebase/google-services.json
if [ "${FIREBASE_DUMMY:-0}" = "1" ]; then
  cat > "$GS" <<'JSON'
{"project_info":{"project_number":"000000000000","project_id":"tinker-ci","storage_bucket":""},
 "client":[{"client_info":{"mobilesdk_app_id":"1:000000000000:android:0000000000000000","android_client_info":{"package_name":"my.otono.tinker"}},"api_key":[{"current_key":"ci-placeholder"}]}]}
JSON
elif [ -n "${PROJECT:-}" ] && [ -n "${ANDROID_APP_ID:-}" ]; then
  TOKEN=$(env -u CLOUDSDK_AUTH_ACCESS_TOKEN gcloud auth print-access-token)
  curl -fsS -H "Authorization: Bearer $TOKEN" \
    "https://firebase.googleapis.com/v1beta1/projects/$PROJECT/androidApps/$ANDROID_APP_ID/config" \
    | python3 -c "import json,sys,base64; open('$GS','wb').write(base64.b64decode(json.load(sys.stdin)['configFileContents']))"
fi
test -s "$GS" || { echo "no $GS: set PROJECT+ANDROID_APP_ID or FIREBASE_DUMMY=1"; exit 1; }

# 2. TinkerPush plugin AAR
(cd android/tinker_push && "$GRADLE" --no-daemon -q assembleRelease)
mkdir -p game/addons/tinker_push/bin
cp android/tinker_push/build/outputs/aar/tinker_push-release.aar game/addons/tinker_push/bin/

# 3. Godot import, Android build template (Gradle), mirror + Firebase resources
godot --headless --path game --import >/dev/null 2>&1 || true
if [ ! -f game/android/build/build.gradle ]; then
  godot --headless --path game --install-android-build-template --quit >/dev/null 2>&1 || true
fi
python3 tools/android_prepare.py "$GS"

# 4. Exports
rm -rf build/web build/download && mkdir -p build/web build/download
godot --headless --path game --export-release Web ../build/web/index.html >/dev/null 2>&1
test -s build/web/index.wasm && test -s build/web/index.pck
if [ ! -f build/debug.keystore ]; then
  keytool -genkeypair -keystore build/debug.keystore -alias androiddebugkey -keyalg RSA -keysize 2048 -validity 10000 \
    -storepass android -keypass android -dname "CN=Android Debug,O=Android,C=US" >/dev/null 2>&1
fi
GODOT_ANDROID_KEYSTORE_DEBUG_PATH=$PWD/build/debug.keystore GODOT_ANDROID_KEYSTORE_DEBUG_USER=androiddebugkey \
GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD=android godot --headless --path game --export-debug Android ../build/download/tinker.apk >/tmp/android_export.log 2>&1 \
  || { tail -40 /tmp/android_export.log; exit 1; }
rm -f build/download/*.idsig
test -s build/download/tinker.apk
echo "clients: web $(du -sh build/web | cut -f1), apk $(du -sh build/download/tinker.apk | cut -f1)"
