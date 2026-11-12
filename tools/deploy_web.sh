#!/usr/bin/env bash
# Clean release build of the web app + deploy to Firebase Hosting.
#
# Always does `flutter clean` first: an incremental web build can keep a stale
# plugin registrant (it once left out firebase_auth, so login failed on the
# live site with a "dev.flutter.pigeon...signInWithEmailAndPassword" error).
#
# Usage:  ./tools/deploy_web.sh            (build + deploy hosting)
#         ./tools/deploy_web.sh --rules    (also deploy Firestore rules + indexes)
set -euo pipefail
cd "$(dirname "$0")/.."

# `flutter clean` deletes build/, which a running `flutter run -d chrome`
# serves its assets from: that session then shows 404s for
# assets/FontManifest.json and shaders. Restart `flutter run` afterwards.
if pgrep -f "[f]lutter_tools.*run" >/dev/null 2>&1; then
  echo "NOTE: a 'flutter run' session is open. After this deploy, stop it (q) and run it again." >&2
fi

flutter clean
flutter pub get

# The Firebase JS SDK is served from web/firebasejs/<version>/ (see
# web/index.html). Its version must match what FlutterFire expects.
FB_CORE_WEB_DIR=$(python3 -c "import json;print([p['rootUri'] for p in json.load(open('.dart_tool/package_config.json'))['packages'] if p['name']=='firebase_core_web'][0].replace('file://',''))")
FB_JS_VERSION=$(grep -o "supportedFirebaseJsSdkVersion = '[^']*'" "$FB_CORE_WEB_DIR/lib/src/firebase_sdk_version.dart" | cut -d"'" -f2)
if [ ! -f "web/firebasejs/$FB_JS_VERSION/firebase-app.js" ] || ! grep -q "firebasejs/$FB_JS_VERSION/" web/index.html; then
  echo "ERROR: FlutterFire now needs Firebase JS SDK $FB_JS_VERSION." >&2
  echo "Download it into web/firebasejs/$FB_JS_VERSION/ and update web/index.html. Not deploying." >&2
  exit 1
fi

flutter build web --release

# Safety check: the login plugin must be in the build.
if [ "$(grep -o 'signInWithEmailAndPassword' build/web/main.dart.js | wc -l)" -lt 2 ]; then
  echo "ERROR: Firebase Auth (web) is missing from the build. Not deploying." >&2
  exit 1
fi

if [ "${1:-}" = "--rules" ]; then
  # Firestore rules + indexes. Storage rules (menu photos) are left out: they
  # need a Storage bucket, which the free Spark plan can't create. Deploy them
  # with `firebase deploy --only storage` once Storage is enabled.
  firebase deploy --only hosting,firestore:rules,firestore:indexes
else
  firebase deploy --only hosting
fi
echo "Done. Open the site and press Ctrl+Shift+R once to load the new version."
